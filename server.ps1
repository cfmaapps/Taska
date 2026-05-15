$port = 8080
$appRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$appRoot = [System.IO.Path]::GetFullPath($appRoot)
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $appRoot))
$appUrlSegment = 'Timewrap'
$AttachmentScanMaxBytes = 6 * 1024 * 1024
$AttachmentScanMaxChars = 12000
$AttachmentScanMaxPerMessage = 8
$OutlookScanMaxItemsPerFolder = 120

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [hashtable]$Body
    )

    $json = $Body | ConvertTo-Json -Compress -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-TextResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body
    )

    if ($null -eq $Body) { $Body = '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Read-JsonRequestBody {
    param([System.Net.HttpListenerRequest]$Request)

    $encoding = $Request.ContentEncoding
    if ($null -eq $encoding) { $encoding = [System.Text.Encoding]::UTF8 }
    $reader = [System.IO.StreamReader]::new($Request.InputStream, $encoding)
    try {
        $body = $reader.ReadToEnd()
    } finally {
        $reader.Close()
    }

    if ([string]::IsNullOrWhiteSpace($body)) { return $null }
    return $body | ConvertFrom-Json
}

function Get-JobNumber {
    param([string]$JobText)

    [int]$jobNum = 0
    if ([string]::IsNullOrWhiteSpace($JobText)) { return $null }
    $JobText = $JobText.Trim()
    if ([int]::TryParse($JobText, [ref]$jobNum) -and $jobNum -ge 100) {
        return $jobNum
    }
    return $null
}

function Get-SafeFileName {
    param([string]$FileName)

    $name = [System.IO.Path]::GetFileName($FileName)
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'email.msg' }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $name = $name.Replace($char, '_')
    }
    return $name.Trim()
}

function Get-UniqueFilePath {
    param(
        [string]$Folder,
        [string]$FileName
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    $candidate = Join-Path $Folder $FileName
    $i = 2
    while (Test-Path $candidate) {
        $candidate = Join-Path $Folder "$baseName ($i)$ext"
        $i++
    }
    return $candidate
}

function Get-AppFilePath {
    param([string]$RelativePath)

    $relative = if ($null -eq $RelativePath) { '' } else { [string]$RelativePath }
    $relative = [System.Uri]::UnescapeDataString($relative)
    $relative = $relative.Replace('/', '\').TrimStart('\')

    $segmentPrefix = "$appUrlSegment\"
    if ($relative.Equals($appUrlSegment, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = ''
    } elseif ($relative.StartsWith($segmentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $relative.Substring($segmentPrefix.Length)
    }

    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $appRoot $relative))
    $appPrefix = $appRoot.TrimEnd('\') + '\'
    if (($fullPath -ne $appRoot) -and (-not $fullPath.StartsWith($appPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        return $null
    }

    return $fullPath
}

function Get-AppRelativePath {
    param([string]$RelativePath)

    $relative = if ($null -eq $RelativePath) { '' } else { [string]$RelativePath }
    $relative = $relative.Replace('/', '\').TrimStart('\')
    $segmentPrefix = "$appUrlSegment\"
    if ($relative.StartsWith($segmentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $relative
    }
    return "$appUrlSegment\$relative"
}

function ConvertTo-IsoDate {
    param([object]$Value)

    if ($null -eq $Value) { return $null }

    try {
        $date = [datetime]$Value
        if ($date.Year -lt 1902) { return $null }
        return $date.ToUniversalTime().ToString('o')
    } catch {
        return $null
    }
}

function Get-EmlSentAt {
    param([string]$FilePath)

    try {
        $reader = [System.IO.StreamReader]::new($FilePath, [System.Text.Encoding]::UTF8, $true)
        try {
            $buffer = New-Object char[] 65536
            $read = $reader.ReadBlock($buffer, 0, $buffer.Length)
        } finally {
            $reader.Close()
        }

        if ($read -le 0) { return $null }
        $text = -join $buffer[0..($read - 1)]
        $headerEnd = $text.IndexOf("`r`n`r`n")
        if ($headerEnd -lt 0) { $headerEnd = $text.IndexOf("`n`n") }
        $headers = if ($headerEnd -ge 0) { $text.Substring(0, $headerEnd) } else { $text }
        $headers = [regex]::Replace($headers, "(`r`n|`n)[ `t]+", ' ')
        $match = [regex]::Match($headers, '(?im)^Date:\s*(.+)$')
        if (-not $match.Success) { return $null }

        $date = [datetimeoffset]::Parse(
            $match.Groups[1].Value.Trim(),
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
        )
        return $date.UtcDateTime.ToString('o')
    } catch {
        return $null
    }
}

function Get-MsgSentAt {
    param([string]$FilePath)

    $outlook = $null
    $item = $null
    try {
        $outlook = Get-RunningOutlookApplication
        if ($null -eq $outlook) { return $null }
        $item = $outlook.Session.OpenSharedItem($FilePath)

        try {
            $sentValue = $item.SentOn
            $sentAt = ConvertTo-IsoDate -Value $sentValue
            if ($sentAt) { return $sentAt }
        } catch {}

        try {
            $receivedValue = $item.ReceivedTime
            return ConvertTo-IsoDate -Value $receivedValue
        } catch {
            return $null
        }
    } catch {
        return $null
    } finally {
        if ($null -ne $item) {
            try { $item.Close(1) | Out-Null } catch {}
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($item) } catch {}
        }
        if ($null -ne $outlook) {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) } catch {}
        }
    }
}

function Get-EmailSentAt {
    param([string]$FilePath)

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($ext -eq '.eml') { return Get-EmlSentAt -FilePath $FilePath }
    if ($ext -eq '.msg') { return Get-MsgSentAt -FilePath $FilePath }
    return $null
}

function Get-RunningOutlookApplication {
    try {
        return [System.Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    } catch {}

    try {
        return New-Object -ComObject Outlook.Application
    } catch {}

    return $null
}

function Get-TimewrapSecretsPath {
    return (Get-AppFilePath '.timewrap-secrets.json')
}

function Get-TimewrapSecrets {
    $path = Get-TimewrapSecretsPath
    if (-not (Test-Path $path -PathType Leaf)) { return [ordered]@{} }

    try {
        $raw = Get-Content -Path $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
        $obj = $raw | ConvertFrom-Json
        $secrets = [ordered]@{}
        foreach ($prop in $obj.PSObject.Properties) {
            $secrets[$prop.Name] = $prop.Value
        }
        return $secrets
    } catch {
        return [ordered]@{}
    }
}

function Save-TimewrapSecrets {
    param([object]$Secrets)

    $path = Get-TimewrapSecretsPath
    $json = $Secrets | ConvertTo-Json -Depth 6
    Set-Content -Path $path -Value $json -Encoding UTF8
}

function Get-OpenAiApiKey {
    if (-not [string]::IsNullOrWhiteSpace($env:TIMEWRAP_OPENAI_API_KEY)) {
        return @{ key = [string]$env:TIMEWRAP_OPENAI_API_KEY; source = 'TIMEWRAP_OPENAI_API_KEY' }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
        return @{ key = [string]$env:OPENAI_API_KEY; source = 'OPENAI_API_KEY' }
    }

    $secrets = Get-TimewrapSecrets
    $stored = [string]$secrets['openaiApiKey']
    if (-not [string]::IsNullOrWhiteSpace($stored)) {
        return @{ key = $stored; source = 'local secrets file' }
    }

    return @{ key = ''; source = '' }
}

function Get-OpenAiModel {
    if (-not [string]::IsNullOrWhiteSpace($env:TIMEWRAP_OPENAI_MODEL)) {
        return [string]$env:TIMEWRAP_OPENAI_MODEL
    }

    $secrets = Get-TimewrapSecrets
    $stored = [string]$secrets['openaiModel']
    if (-not [string]::IsNullOrWhiteSpace($stored)) { return $stored }

    return 'gpt-5.4-mini'
}

function ConvertTo-ValidUtf16Text {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = [char]$Text[$i]
        $code = [int]$ch

        if ($code -ge 0xD800 -and $code -le 0xDBFF) {
            if ($i + 1 -lt $Text.Length) {
                $next = [char]$Text[$i + 1]
                $nextCode = [int]$next
                if ($nextCode -ge 0xDC00 -and $nextCode -le 0xDFFF) {
                    [void]$sb.Append($ch)
                    [void]$sb.Append($next)
                    $i += 2
                    continue
                }
            }
            [void]$sb.Append(' ')
        } elseif ($code -ge 0xDC00 -and $code -le 0xDFFF) {
            [void]$sb.Append(' ')
        } elseif ($code -lt 0x20 -and $code -ne 9 -and $code -ne 10 -and $code -ne 13) {
            [void]$sb.Append(' ')
        } else {
            [void]$sb.Append($ch)
        }

        $i++
    }

    return $sb.ToString()
}

function ConvertTo-SafeAiText {
    param(
        [object]$Value,
        [int]$MaxLength = 12000
    )

    if ($null -eq $Value) { return '' }
    $text = ConvertTo-ValidUtf16Text ([string]$Value)
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if ($text.Length -gt $MaxLength) { return $text.Substring(0, $MaxLength) }
    return $text
}

function Normalize-AiDateString {
    param([object]$Value)

    $text = ConvertTo-SafeAiText $Value 32
    if ($text -match '^\d{4}-\d{2}-\d{2}$') { return $text }
    return ''
}

function Normalize-AiTimeString {
    param([object]$Value)

    $text = ConvertTo-SafeAiText $Value 16
    if ($text -match '^([01]\d|2[0-3]):[0-5]\d$') { return $text }
    return ''
}

function Normalize-AiKind {
    param([object]$Value)

    $kind = (ConvertTo-SafeAiText $Value 24).ToLowerInvariant()
    if (@('task', 'meeting', 'stay', 'paid', 'info', 'person') -contains $kind) { return $kind }
    return 'task'
}

function Get-AiAttachmentSummary {
    param([object]$Message)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($attachment in @($Message.attachments)) {
        if ($null -eq $attachment) { continue }
        $name = ''
        if ($attachment -is [string]) {
            $name = ConvertTo-SafeAiText $attachment 160
        } elseif ($attachment.PSObject.Properties.Name -contains 'name') {
            $name = ConvertTo-SafeAiText $attachment.name 160
            $kind = ConvertTo-SafeAiText $attachment.kind 40
            $size = ConvertTo-SafeAiText $attachment.size 30
            if (-not [string]::IsNullOrWhiteSpace($kind)) { $name = "$name ($kind)" }
            if (-not [string]::IsNullOrWhiteSpace($size) -and $size -ne '0') { $name = "$name $size bytes" }
        }
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$names.Add($name) }
    }

    foreach ($name in @($Message.attachmentNames)) {
        $safe = ConvertTo-SafeAiText $name 160
        if (-not [string]::IsNullOrWhiteSpace($safe) -and -not $names.Contains($safe)) {
            [void]$names.Add($safe)
        }
    }

    return ($names.ToArray() | Select-Object -First 12) -join ', '
}

function Get-AiEmailGroups {
    param([object]$Payload)

    $maxGroups = 80
    if (-not [string]::IsNullOrWhiteSpace($env:TIMEWRAP_AI_MAX_GROUPS)) {
        [int]$parsedMax = 0
        if ([int]::TryParse($env:TIMEWRAP_AI_MAX_GROUPS, [ref]$parsedMax) -and $parsedMax -gt 0) {
            $maxGroups = [math]::Min($parsedMax, 180)
        }
    }

    $groups = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($message in @($Payload.messages)) {
        if ($null -eq $message) { continue }

        $id = ConvertTo-SafeAiText $message.id 120
        $threadId = ConvertTo-SafeAiText $message.threadId 120
        $groupKey = if (-not [string]::IsNullOrWhiteSpace($threadId)) { "thread:$threadId" } else { "message:$id" }
        if ([string]::IsNullOrWhiteSpace($groupKey) -or $groupKey -eq 'message:') { continue }

        if (-not $groups.ContainsKey($groupKey)) {
            $groupId = 'g' + ($groups.Count + 1)
            $groups[$groupKey] = [ordered]@{
                groupId = $groupId
                groupKey = $groupKey
                messageId = $id
                threadId = $threadId
                date = ConvertTo-SafeAiText $message.date 80
                subject = ConvertTo-SafeAiText $message.subject 240
                from = ConvertTo-SafeAiText $message.from 240
                to = ConvertTo-SafeAiText $message.to 240
                source = ConvertTo-SafeAiText $message.source 40
                parts = @()
            }
            [void]$order.Add($groupKey)
        }

        $attachmentNames = Get-AiAttachmentSummary -Message $message
        $bodySource = $message.cleanedBodyText
        if ([string]::IsNullOrWhiteSpace([string]$bodySource)) { $bodySource = $message.body }
        $bodyText = ConvertTo-SafeAiText $bodySource 4500
        $plainText = ConvertTo-SafeAiText $message.plainTextBody 2500

        $parts = @(
            "Subject: $(ConvertTo-SafeAiText $message.subject 300)",
            "From: $(ConvertTo-SafeAiText $message.from 260)",
            "To: $(ConvertTo-SafeAiText $message.to 260)",
            "Received: $(ConvertTo-SafeAiText $message.date 80)",
            "Source: $(ConvertTo-SafeAiText $message.source 40)",
            "Labels: $((@($message.labels) | ForEach-Object { ConvertTo-SafeAiText $_ 60 }) -join ', ')",
            "Attachments: $attachmentNames",
            "Snippet: $(ConvertTo-SafeAiText $message.snippet 1000)",
            "Plain text: $plainText",
            "Body: $bodyText",
            "Thread text: $(ConvertTo-SafeAiText $message.threadText 6500)",
            "Attachment text: $(ConvertTo-SafeAiText $message.attachmentText 6500)"
        )
        $groups[$groupKey]['parts'] += (ConvertTo-SafeAiText ($parts -join "`n") 14000)
    }

    $emails = New-Object System.Collections.Generic.List[object]
    $lookup = @{}
    foreach ($key in $order) {
        if ($emails.Count -ge $maxGroups) { break }
        $group = $groups[$key]
        $text = ConvertTo-SafeAiText (($group['parts'] -join "`n--- same Gmail thread ---`n")) 14000
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $email = [ordered]@{
            groupId = $group['groupId']
            receivedDate = $group['date']
            subject = $group['subject']
            from = $group['from']
            source = $group['source']
            text = $text
        }
        [void]$emails.Add($email)
        $lookup[$group['groupId']] = $group
    }

    return @{ emails = $emails.ToArray(); lookup = $lookup; totalGroups = $order.Count }
}

function New-TimewrapEmailExtractionSchema {
    return [ordered]@{
        type = 'object'
        additionalProperties = $false
        required = @('items')
        properties = [ordered]@{
            items = [ordered]@{
                type = 'array'
                items = [ordered]@{
                    type = 'object'
                    additionalProperties = $false
                    required = @('groupId', 'kind', 'title', 'date', 'endDate', 'time', 'amount', 'needsDate', 'confidence', 'evidence', 'reason', 'rawDate')
                    properties = [ordered]@{
                        groupId = [ordered]@{ type = 'string' }
                        kind = [ordered]@{ type = 'string'; enum = @('task', 'meeting', 'stay', 'paid', 'info', 'person') }
                        title = [ordered]@{ type = 'string' }
                        date = [ordered]@{ type = 'string' }
                        endDate = [ordered]@{ type = 'string' }
                        time = [ordered]@{ type = 'string' }
                        amount = [ordered]@{ type = 'string' }
                        needsDate = [ordered]@{ type = 'boolean' }
                        confidence = [ordered]@{ type = 'number' }
                        evidence = [ordered]@{ type = 'string' }
                        reason = [ordered]@{ type = 'string' }
                        rawDate = [ordered]@{ type = 'string' }
                    }
                }
            }
        }
    }
}

function Get-OpenAiOutputText {
    param([object]$Response)

    if ($null -eq $Response) { return '' }
    if ($Response.PSObject.Properties.Name -contains 'output_text') {
        $direct = [string]$Response.output_text
        if (-not [string]::IsNullOrWhiteSpace($direct)) { return $direct }
    }

    foreach ($output in @($Response.output)) {
        foreach ($content in @($output.content)) {
            if ([string]$content.type -eq 'output_text') {
                $text = [string]$content.text
                if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
            }
        }
    }
    return ''
}

function Invoke-TimewrapOpenAiExtraction {
    param(
        [object]$Payload,
        [array]$Emails
    )

    $api = Get-OpenAiApiKey
    if ([string]::IsNullOrWhiteSpace($api.key)) {
        throw 'AI is not configured. Click AI Setup and paste an OpenAI API key, or set OPENAI_API_KEY before starting the server.'
    }

    $today = ConvertTo-SafeAiText $Payload.today 32
    if ([string]::IsNullOrWhiteSpace($today)) { $today = (Get-Date).ToString('yyyy-MM-dd') }
    $timezone = ConvertTo-SafeAiText $Payload.timezone 80
    if ([string]::IsNullOrWhiteSpace($timezone)) { $timezone = 'Pacific/Auckland' }

    $userPayload = [ordered]@{
        today = $today
        timezone = $timezone
        emails = $Emails
    }

    $systemPrompt = @"
You extract useful calendar and reminder items from Gmail scan text for a New Zealand work/personal planning tool.
Return JSON only through the provided schema.

Rules:
- Extract bills, invoices, rates, power bills, due dates, payment confirmations, appointments, accountant/tax dates, confirmed Airbnb stays, and real-person reply follow-ups.
- Ignore marketing/promotions/newsletters unless they contain a concrete due date, booking, appointment, amount owing, or payment confirmation.
- Person follow-ups are only for emails that look like a real person is waiting for a reply. Do not create person items for automated businesses, newsletters, travel loyalty programs, restaurants, groceries, or promotions.
- Ignore Ben Terry, Marianne Beer, Bread and Bull, Bread & Bull, and Independent Reserve.
- Airbnb stays must be confirmed/accepted bookings only. If a confirmed Airbnb thread also contains an earlier request email, use that earlier requested email for the start/arrives date and number of nights.
- For Airbnb nights, date is the arrival/start/check-in date. If only a start date and number of nights are known, endDate is start date plus nights minus one day. If no confirmed/accepted booking signal exists, do not create an Airbnb stay.
- Dates must be yyyy-mm-dd. Times must be HH:mm 24-hour or empty.
- If an item is clearly useful but no date is available, set date and endDate to empty strings, needsDate true, and explain that the received date should be used as a placeholder.
- Include amount like `$392.50` or `NZD 392.50` when a bill/payment amount is visible.
- Keep evidence short and quote the exact clue text where possible.
- Confidence is 0 to 1. Use higher confidence only when the email text clearly supports the item.
"@

    $requestBody = [ordered]@{
        model = Get-OpenAiModel
        input = @(
            [ordered]@{ role = 'system'; content = $systemPrompt },
            [ordered]@{ role = 'user'; content = ($userPayload | ConvertTo-Json -Depth 8 -Compress) }
        )
        text = [ordered]@{
            format = [ordered]@{
                type = 'json_schema'
                name = 'timewrap_email_calendar_items'
                strict = $true
                schema = (New-TimewrapEmailExtractionSchema)
            }
        }
        max_output_tokens = 6000
    }

    $json = $requestBody | ConvertTo-Json -Depth 20 -Compress
    $headers = @{
        Authorization = "Bearer $($api.key)"
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response = Invoke-RestMethod -Uri 'https://api.openai.com/v1/responses' -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 120
        $outputText = Get-OpenAiOutputText -Response $response
        if ([string]::IsNullOrWhiteSpace($outputText)) {
            throw 'OpenAI returned no structured output.'
        }
        return ($outputText | ConvertFrom-Json)
    } catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } elseif ($_.Exception) { $_.Exception.Message } else { [string]$_ }
        throw "AI extraction failed. $detail"
    }
}

function Convert-AiExtractionToCalendarItems {
    param(
        [object]$AiResult,
        [hashtable]$GroupLookup
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($rawItem in @($AiResult.items)) {
        if ($null -eq $rawItem) { continue }
        $groupId = ConvertTo-SafeAiText $rawItem.groupId 40
        if (-not $GroupLookup.ContainsKey($groupId)) { continue }

        $group = $GroupLookup[$groupId]
        $kind = Normalize-AiKind $rawItem.kind
        $title = ConvertTo-SafeAiText $rawItem.title 180
        if ([string]::IsNullOrWhiteSpace($title)) { $title = 'Gmail item' }
        $date = Normalize-AiDateString $rawItem.date
        $endDate = Normalize-AiDateString $rawItem.endDate
        $time = Normalize-AiTimeString $rawItem.time
        $amount = ConvertTo-SafeAiText $rawItem.amount 60
        $evidence = ConvertTo-SafeAiText $rawItem.evidence 360
        $reason = ConvertTo-SafeAiText $rawItem.reason 260
        $rawDate = ConvertTo-SafeAiText $rawItem.rawDate 120
        $confidence = 0.0
        try { $confidence = [double]$rawItem.confidence } catch {}
        if ($confidence -lt 0.35) { continue }

        $needsDate = ($true -eq $rawItem.needsDate) -or [string]::IsNullOrWhiteSpace($date)
        $context = ConvertTo-SafeAiText (($evidence, $reason | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' - ') 520
        $sourceKeyTitle = (ConvertTo-SafeAiText $title 80).ToLowerInvariant()
        $sourceKey = "ai|$($group['groupKey'])|$kind|$date|$endDate|$time|$sourceKeyTitle|$amount"

        [void]$items.Add([ordered]@{
            sourceKey = $sourceKey
            kind = $kind
            needsDate = $needsDate
            date = $date
            endDate = $endDate
            time = $time
            title = $title
            amount = $amount
            context = $context
            rawDate = if ([string]::IsNullOrWhiteSpace($rawDate)) { if ($needsDate) { 'Needs date' } else { $date } } else { $rawDate }
            sourceSubject = $group['subject']
            sourceFrom = $group['from']
            sourceDate = $group['date']
            searchText = $group['parts'] -join ' '
            confidence = [math]::Round($confidence, 2)
            message = [ordered]@{
                id = $group['messageId']
                threadId = $group['threadId']
                date = $group['date']
                subject = $group['subject']
                from = $group['from']
                source = $group['source']
                snippet = $evidence
            }
        })
    }

    return @($items)
}

function New-TimewrapOutlookTriageSchema {
    return [ordered]@{
        type = 'object'
        additionalProperties = $false
        required = @('items')
        properties = [ordered]@{
            items = [ordered]@{
                type = 'array'
                items = [ordered]@{
                    type = 'object'
                    additionalProperties = $false
                    required = @('groupKey', 'status', 'jobId', 'jobNum', 'jobLabel', 'confidence', 'reason', 'recommendedTaskName', 'suggestedJobNum', 'suggestedJobDescription', 'actionSummary', 'priority')
                    properties = [ordered]@{
                        groupKey = [ordered]@{ type = 'string' }
                        status = [ordered]@{ type = 'string'; enum = @('existing_job', 'new_job', 'unrelated', 'needs_review') }
                        jobId = [ordered]@{ type = 'string' }
                        jobNum = [ordered]@{ type = 'string' }
                        jobLabel = [ordered]@{ type = 'string' }
                        confidence = [ordered]@{ type = 'number' }
                        reason = [ordered]@{ type = 'string' }
                        recommendedTaskName = [ordered]@{ type = 'string' }
                        suggestedJobNum = [ordered]@{ type = 'string' }
                        suggestedJobDescription = [ordered]@{ type = 'string' }
                        actionSummary = [ordered]@{ type = 'string' }
                        priority = [ordered]@{ type = 'string'; enum = @('urgent', 'soon', 'normal', 'low') }
                    }
                }
            }
        }
    }
}

function New-TimewrapWeeklyBriefingSchema {
    return [ordered]@{
        type = 'object'
        additionalProperties = $false
        required = @('title', 'intro', 'sections', 'closing')
        properties = [ordered]@{
            title = [ordered]@{ type = 'string' }
            intro = [ordered]@{ type = 'string' }
            sections = [ordered]@{
                type = 'array'
                items = [ordered]@{
                    type = 'object'
                    additionalProperties = $false
                    required = @('heading', 'body', 'items')
                    properties = [ordered]@{
                        heading = [ordered]@{ type = 'string' }
                        body = [ordered]@{ type = 'string' }
                        items = [ordered]@{
                            type = 'array'
                            items = [ordered]@{ type = 'string' }
                        }
                    }
                }
            }
            closing = [ordered]@{ type = 'string' }
        }
    }
}

function Get-OutlookAiGroupsFromPayload {
    param([object]$Payload)

    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($Payload.groups)) {
        if ($null -eq $group) { continue }
        $key = ConvertTo-SafeAiText $group.key 160
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        $messageParts = New-Object System.Collections.Generic.List[string]
        foreach ($message in @($group.messages)) {
            if ($null -eq $message) { continue }
            $attachmentNames = Get-AiAttachmentSummary -Message $message
            $body = ConvertTo-SafeAiText $message.body 2600
            $preview = ConvertTo-SafeAiText $message.preview 1000
            [void]$messageParts.Add((@(
                "Direction: $(ConvertTo-SafeAiText $message.direction 24)",
                "Subject: $(ConvertTo-SafeAiText $message.subject 260)",
                "Sender: $(ConvertTo-SafeAiText $message.sender 220) <$(ConvertTo-SafeAiText $message.senderEmail 180)>",
                "Recipients: $(ConvertTo-SafeAiText $message.recipients 260)",
                "Date: $(ConvertTo-SafeAiText $message.date 80)",
                "Attachments: $attachmentNames",
                "Preview: $preview",
                "Body: $body",
                "Attachment text: $(ConvertTo-SafeAiText $message.attachmentText 2800)"
            ) -join "`n"))
        }

        [void]$groups.Add([ordered]@{
            key = $key
            direction = ConvertTo-SafeAiText $group.direction 24
            subject = ConvertTo-SafeAiText $group.subject 260
            localBestJobId = ConvertTo-SafeAiText $group.localBestJobId 120
            localBestJobLabel = ConvertTo-SafeAiText $group.localBestJobLabel 260
            localBestScore = ConvertTo-SafeAiText $group.localBestScore 32
            text = ConvertTo-SafeAiText (($messageParts.ToArray() | Select-Object -First 4) -join "`n--- same Outlook conversation ---`n") 13000
        })
    }

    return @($groups.ToArray() | Select-Object -First 80)
}

function Get-OutlookAiJobsFromPayload {
    param([object]$Payload)

    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($job in @($Payload.jobs)) {
        if ($null -eq $job) { continue }
        $tasks = New-Object System.Collections.Generic.List[string]
        foreach ($task in @($job.tasks)) {
            if ($null -eq $task -or $true -eq $task.done) { continue }
            $label = ConvertTo-SafeAiText $task.text 180
            $due = ConvertTo-SafeAiText $task.dueDate 40
            if (-not [string]::IsNullOrWhiteSpace($due)) { $label = "$label (due $due)" }
            if (-not [string]::IsNullOrWhiteSpace($label)) { [void]$tasks.Add($label) }
        }
        [void]$jobs.Add([ordered]@{
            id = ConvertTo-SafeAiText $job.id 120
            jobNum = ConvertTo-SafeAiText $job.jobNum 40
            desc = ConvertTo-SafeAiText $job.desc 240
            priority = ConvertTo-SafeAiText $job.priority 40
            dormant = $true -eq $job.dormant
            openTasks = @($tasks.ToArray() | Select-Object -First 12)
        })
    }

    return @($jobs.ToArray() | Select-Object -First 260)
}

function Invoke-TimewrapOutlookTriage {
    param([object]$Payload)

    $api = Get-OpenAiApiKey
    if ([string]::IsNullOrWhiteSpace($api.key)) {
        throw 'AI is not configured. Click AI Setup and paste an OpenAI API key, or set OPENAI_API_KEY before starting the server.'
    }

    $userPayload = [ordered]@{
        today = ConvertTo-SafeAiText $Payload.today 32
        timezone = ConvertTo-SafeAiText $Payload.timezone 80
        jobs = Get-OutlookAiJobsFromPayload -Payload $Payload
        groups = Get-OutlookAiGroupsFromPayload -Payload $Payload
    }

    $systemPrompt = @"
You triage Outlook conversations for a New Zealand survey/work planning app.
Return JSON only through the provided schema.

For each Outlook conversation:
- Decide whether it belongs to one existing job, should become a new job, is unrelated/low-value, or needs manual review.
- Match existing jobs using job number, client/site names, job descriptions, task names, legal/site/project context, and email content.
- Prefer existing_job only when the evidence is strong. Use needs_review when plausible but uncertain.
- Use new_job when it looks like real work but no existing job fits. Suggest a concise job description and a job number only if one is visible in the email.
- Use unrelated for newsletters, generic notifications, receipts with no job context, spam, or emails with no survey/work action.
- Recommend a short task name written as an action, for example "Reply re road naming", "Book site inspection", "Send updated survey plan".
- Keep reasons specific and short.
- Confidence is 0 to 1.
"@

    $requestBody = [ordered]@{
        model = Get-OpenAiModel
        input = @(
            [ordered]@{ role = 'system'; content = $systemPrompt },
            [ordered]@{ role = 'user'; content = ($userPayload | ConvertTo-Json -Depth 12 -Compress) }
        )
        text = [ordered]@{
            format = [ordered]@{
                type = 'json_schema'
                name = 'timewrap_outlook_triage'
                strict = $true
                schema = (New-TimewrapOutlookTriageSchema)
            }
        }
        max_output_tokens = 7000
    }

    $json = $requestBody | ConvertTo-Json -Depth 20 -Compress
    $headers = @{ Authorization = "Bearer $($api.key)" }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response = Invoke-RestMethod -Uri 'https://api.openai.com/v1/responses' -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 120
        $outputText = Get-OpenAiOutputText -Response $response
        if ([string]::IsNullOrWhiteSpace($outputText)) { throw 'OpenAI returned no structured output.' }
        return ($outputText | ConvertFrom-Json)
    } catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } elseif ($_.Exception) { $_.Exception.Message } else { [string]$_ }
        throw "Outlook AI triage failed. $detail"
    }
}

function Invoke-TimewrapWeeklyBriefing {
    param([object]$Payload)

    $api = Get-OpenAiApiKey
    if ([string]::IsNullOrWhiteSpace($api.key)) {
        throw 'AI is not configured. Click AI Setup and paste an OpenAI API key, or set OPENAI_API_KEY before starting the server.'
    }

    $userPayload = [ordered]@{
        today = ConvertTo-SafeAiText $Payload.today 32
        timezone = ConvertTo-SafeAiText $Payload.timezone 80
        jobs = @($Payload.jobs)
        outlookRecommendations = @($Payload.outlookRecommendations)
        gmailItems = @($Payload.gmailItems)
    }

    $systemPrompt = @"
You write a concise next-week work briefing for a busy survey/project planner.
Return JSON only through the provided schema.

Style:
- Write like a useful internal newsletter, not a marketing newsletter.
- Be specific about what needs doing, who/what it relates to, and dates.
- Group the week into sections such as Hot Desk, Email Follow-ups, Scheduled Deadlines, and Watch List.
- Prioritise tasks due in the next 7 days, urgent jobs, AI-triaged Outlook follow-ups, and Gmail briefing items.
- Keep it short enough to scan in under two minutes.
"@

    $requestBody = [ordered]@{
        model = Get-OpenAiModel
        input = @(
            [ordered]@{ role = 'system'; content = $systemPrompt },
            [ordered]@{ role = 'user'; content = ($userPayload | ConvertTo-Json -Depth 12 -Compress) }
        )
        text = [ordered]@{
            format = [ordered]@{
                type = 'json_schema'
                name = 'timewrap_weekly_briefing'
                strict = $true
                schema = (New-TimewrapWeeklyBriefingSchema)
            }
        }
        max_output_tokens = 3500
    }

    $json = $requestBody | ConvertTo-Json -Depth 20 -Compress
    $headers = @{ Authorization = "Bearer $($api.key)" }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response = Invoke-RestMethod -Uri 'https://api.openai.com/v1/responses' -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 120
        $outputText = Get-OpenAiOutputText -Response $response
        if ([string]::IsNullOrWhiteSpace($outputText)) { throw 'OpenAI returned no structured output.' }
        return ($outputText | ConvertFrom-Json)
    } catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } elseif ($_.Exception) { $_.Exception.Message } else { [string]$_ }
        throw "Weekly briefing failed. $detail"
    }
}

function Get-ScanStartDate {
    param([string]$Since)

    $start = (Get-Date).AddDays(-14)
    if (-not [string]::IsNullOrWhiteSpace($Since)) {
        try {
            $sinceDate = [datetimeoffset]::Parse($Since).LocalDateTime
            if ($sinceDate -gt $start) { $start = $sinceDate }
        } catch {}
    }
    return $start
}

function Get-OutlookItemDate {
    param(
        [object]$Item,
        [string]$Direction
    )

    try {
        if ($Direction -eq 'sent') {
            $date = [datetime]$Item.SentOn
        } else {
            $date = [datetime]$Item.ReceivedTime
        }
        if ($date.Year -lt 1902) { return $null }
        return $date
    } catch {
        return $null
    }
}

function Get-ShortMailBody {
    param([object]$Item)

    try {
        $body = [string]$Item.Body
        if ([string]::IsNullOrWhiteSpace($body)) { return '' }
        $body = [regex]::Replace($body, '\s+', ' ').Trim()
        if ($body.Length -gt 260) { return $body.Substring(0, 260).Trim() + '...' }
        return $body
    } catch {
        return ''
    }
}

function Limit-ScanText {
    param(
        [string]$Text,
        [int]$MaxChars = 12000
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = [regex]::Replace($Text, '\s+', ' ').Trim()
    if ($clean.Length -gt $MaxChars) { return $clean.Substring(0, $MaxChars).Trim() }
    return $clean
}

function Convert-HtmlToScanText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $value = [regex]::Replace($Text, '<style[\s\S]*?</style>', ' ', 'IgnoreCase')
    $value = [regex]::Replace($value, '<script[\s\S]*?</script>', ' ', 'IgnoreCase')
    $value = [regex]::Replace($value, '<[^>]+>', ' ')
    try { $value = [System.Net.WebUtility]::HtmlDecode($value) } catch {}
    return Limit-ScanText -Text $value -MaxChars $AttachmentScanMaxChars
}

function Convert-XmlToScanText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $value = [regex]::Replace($Text, '<[^>]+>', ' ')
    try { $value = [System.Net.WebUtility]::HtmlDecode($value) } catch {}
    return Limit-ScanText -Text $value -MaxChars $AttachmentScanMaxChars
}

function Get-MailBodyForScan {
    param([object]$Item)

    try {
        $body = [string]$Item.Body
        return Limit-ScanText -Text $body -MaxChars 8000
    } catch {
        return ''
    }
}

function Read-TextAttachmentFile {
    param([string]$FilePath)

    try {
        $reader = [System.IO.StreamReader]::new($FilePath, [System.Text.Encoding]::UTF8, $true)
        try {
            return Limit-ScanText -Text $reader.ReadToEnd() -MaxChars $AttachmentScanMaxChars
        } finally {
            $reader.Close()
        }
    } catch {
        return ''
    }
}

function Read-ZipEntryText {
    param(
        [string]$FilePath,
        [string[]]$EntryPatterns
    )

    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
        $text = ''
        foreach ($entry in $zip.Entries) {
            foreach ($pattern in $EntryPatterns) {
                if ($entry.FullName -like $pattern) {
                    $stream = $null
                    $reader = $null
                    try {
                        $stream = $entry.Open()
                        $reader = [System.IO.StreamReader]::new($stream)
                        $text += ' ' + $reader.ReadToEnd()
                    } finally {
                        if ($null -ne $reader) { $reader.Close() }
                        if ($null -ne $stream) { $stream.Close() }
                    }
                    break
                }
            }
        }
        return Convert-XmlToScanText -Text $text
    } catch {
        return ''
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}

function Read-PdfTextWithWord {
    param([string]$FilePath)

    $word = $null
    $doc = $null
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0
        $doc = $word.Documents.Open($FilePath, $false, $true)
        return Limit-ScanText -Text ([string]$doc.Content.Text) -MaxChars $AttachmentScanMaxChars
    } catch {
        return ''
    } finally {
        if ($null -ne $doc) {
            try { $doc.Close($false) | Out-Null } catch {}
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) } catch {}
        }
        if ($null -ne $word) {
            try { $word.Quit() | Out-Null } catch {}
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) } catch {}
        }
    }
}

function Read-RawPdfText {
    param([string]$FilePath)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $latin1 = [System.Text.Encoding]::GetEncoding(28591)
        $raw = $latin1.GetString($bytes)
        $pieces = @()
        foreach ($m in [regex]::Matches($raw, '\((?:\\.|[^\\)]){4,}\)')) {
            $value = $m.Value.Trim('(', ')')
            $value = $value -replace '\\\(', '(' -replace '\\\)', ')' -replace '\\n', ' ' -replace '\\r', ' ' -replace '\\t', ' '
            if ($value -match '[A-Za-z]{3,}') { $pieces += $value }
            if (($pieces -join ' ').Length -gt $AttachmentScanMaxChars) { break }
        }
        return Limit-ScanText -Text ($pieces -join ' ') -MaxChars $AttachmentScanMaxChars
    } catch {
        return ''
    }
}

function Read-AttachmentText {
    param(
        [string]$FilePath,
        [string]$OriginalName
    )

    $ext = [System.IO.Path]::GetExtension($OriginalName).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant() }

    switch ($ext) {
        { $_ -in @('.txt', '.csv', '.tsv', '.ics', '.json', '.log') } {
            return [ordered]@{ text = (Read-TextAttachmentFile -FilePath $FilePath); kind = 'text' }
        }
        { $_ -in @('.html', '.htm', '.xml') } {
            return [ordered]@{ text = (Convert-HtmlToScanText -Text (Read-TextAttachmentFile -FilePath $FilePath)); kind = 'html' }
        }
        '.docx' {
            return [ordered]@{ text = (Read-ZipEntryText -FilePath $FilePath -EntryPatterns @('word/document.xml', 'word/header*.xml', 'word/footer*.xml')); kind = 'docx' }
        }
        '.xlsx' {
            return [ordered]@{ text = (Read-ZipEntryText -FilePath $FilePath -EntryPatterns @('xl/sharedStrings.xml', 'xl/worksheets/*.xml')); kind = 'xlsx' }
        }
        '.pdf' {
            $text = Read-PdfTextWithWord -FilePath $FilePath
            $kind = 'pdf-word'
            if ([string]::IsNullOrWhiteSpace($text)) {
                $text = Read-RawPdfText -FilePath $FilePath
                $kind = 'pdf-raw'
            }
            return [ordered]@{ text = $text; kind = $kind }
        }
        default {
            return [ordered]@{ text = ''; kind = 'unsupported' }
        }
    }
}

function Get-OutlookAttachmentScan {
    param([object]$Item)

    $names = @()
    $items = @()
    $textParts = @()
    $tempFolder = $null

    try {
        $attachments = $Item.Attachments
        $count = [int]$attachments.Count
        if ($count -le 0) {
            return [ordered]@{ names = @(); text = ''; items = @(); count = 0 }
        }

        $rootTemp = Join-Path ([System.IO.Path]::GetTempPath()) 'timewrap-attachment-scan'
        if (-not (Test-Path $rootTemp)) { New-Item -ItemType Directory -Path $rootTemp | Out-Null }
        $tempFolder = Join-Path $rootTemp ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempFolder | Out-Null

        $limit = [Math]::Min($count, $AttachmentScanMaxPerMessage)
        for ($i = 1; $i -le $limit; $i++) {
            $attachment = $null
            $name = "attachment-$i"
            try {
                $attachment = $attachments.Item($i)
                $name = Get-SafeFileName -FileName ([string]$attachment.FileName)
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "attachment-$i" }
                $size = 0
                try { $size = [int64]$attachment.Size } catch {}
                $names += $name

                $scan = [ordered]@{
                    name = $name
                    size = $size
                    scanned = $false
                    kind = 'unsupported'
                    chars = 0
                    error = ''
                }

                if ($size -gt $AttachmentScanMaxBytes) {
                    $scan.kind = 'too-large'
                    $scan.error = 'Skipped large attachment.'
                    $items += $scan
                    continue
                }

                $filePath = Get-UniqueFilePath -Folder $tempFolder -FileName $name
                $attachment.SaveAsFile($filePath)
                $read = Read-AttachmentText -FilePath $filePath -OriginalName $name
                $scan.kind = [string]$read.kind
                $scanText = Limit-ScanText -Text ([string]$read.text) -MaxChars $AttachmentScanMaxChars
                if (-not [string]::IsNullOrWhiteSpace($scanText)) {
                    $scan.scanned = $true
                    $scan.chars = $scanText.Length
                    $textParts += "Attachment ${name}: $scanText"
                }
                $items += $scan
            } catch {
                $items += [ordered]@{
                    name = if ($name) { $name } else { "attachment-$i" }
                    size = 0
                    scanned = $false
                    kind = 'error'
                    chars = 0
                    error = 'Could not scan attachment.'
                }
            } finally {
                if ($null -ne $attachment) {
                    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($attachment) } catch {}
                }
            }
        }

        return [ordered]@{
            names = @($names)
            text = (Limit-ScanText -Text ($textParts -join ' ') -MaxChars $AttachmentScanMaxChars)
            items = @($items)
            count = $count
        }
    } catch {
        return [ordered]@{ names = @($names); text = ''; items = @($items); count = 0 }
    } finally {
        if ($tempFolder -and (Test-Path $tempFolder)) {
            Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OutlookAttachmentMetadata {
    param([object]$Item)

    $names = @()
    $items = @()
    $count = 0

    try {
        $attachments = $Item.Attachments
        $count = [int]$attachments.Count
        if ($count -le 0) {
            return [ordered]@{ names = @(); text = ''; items = @(); count = 0 }
        }

        $limit = [Math]::Min($count, $AttachmentScanMaxPerMessage)
        for ($i = 1; $i -le $limit; $i++) {
            $attachment = $null
            $name = "attachment-$i"
            try {
                $attachment = $attachments.Item($i)
                $name = Get-SafeFileName -FileName ([string]$attachment.FileName)
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "attachment-$i" }
                $size = 0
                try { $size = [int64]$attachment.Size } catch {}
                $names += $name
                $items += [ordered]@{
                    name = $name
                    size = $size
                    scanned = $false
                    kind = 'metadata'
                    chars = 0
                    error = ''
                }
            } catch {
                $items += [ordered]@{
                    name = $name
                    size = 0
                    scanned = $false
                    kind = 'error'
                    chars = 0
                    error = 'Could not read attachment metadata.'
                }
            } finally {
                if ($null -ne $attachment) {
                    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($attachment) } catch {}
                }
            }
        }
    } catch {}

    return [ordered]@{ names = @($names); text = ''; items = @($items); count = $count }
}

function Get-CleanSubject {
    param([string]$Subject)

    if ([string]::IsNullOrWhiteSpace($Subject)) { return '(No subject)' }
    return ([regex]::Replace($Subject, '^\s*(re|fw|fwd)\s*:\s*', '', 'IgnoreCase')).Trim()
}

function Get-OutlookFileName {
    param(
        [object]$Item,
        [datetime]$Date
    )

    $subject = Get-CleanSubject -Subject ([string]$Item.Subject)
    $subject = [regex]::Replace($subject, '\s+', ' ').Trim()
    if ($subject.Length -gt 90) { $subject = $subject.Substring(0, 90).Trim() }
    $stamp = $Date.ToString('yyyy-MM-dd HHmm')
    return Get-SafeFileName -FileName "$stamp - $subject.msg"
}

function Get-OutlookFolderMessages {
    param(
        [object]$Folder,
        [string]$Direction,
        [datetime]$StartDate,
        [int]$MaxItems = 120,
        [string]$FolderLabel = ''
    )

    $messages = @()
    if ($null -eq $Folder) { return $messages }
    if ([string]::IsNullOrWhiteSpace($FolderLabel)) { $FolderLabel = $Direction }
    Write-Host "  [Outlook] Reading $FolderLabel (max $MaxItems messages)..." -ForegroundColor DarkCyan

    $items = $Folder.Items
    $sortField = if ($Direction -eq 'sent') { '[SentOn]' } else { '[ReceivedTime]' }
    $isSorted = $false
    try {
        $items.Sort($sortField, $true)
        $isSorted = $true
    } catch {}

    $checked = 0
    foreach ($item in $items) {
        try {
            if ([int]$item.Class -ne 43) { continue }
            $checked++
            if ($checked -eq 1 -or $checked % 25 -eq 0) {
                Write-Host "  [Outlook] $FolderLabel checked $checked item(s), kept $($messages.Count)..." -ForegroundColor DarkGray
            }
            $date = Get-OutlookItemDate -Item $item -Direction $Direction
            if ($null -eq $date) { continue }
            if ($date -lt $StartDate) {
                if ($isSorted) { break }
                continue
            }

            $entryId = [string]$item.EntryID
            if ([string]::IsNullOrWhiteSpace($entryId)) { continue }

            $conversationId = ''
            try { $conversationId = [string]$item.ConversationID } catch {}
            if ([string]::IsNullOrWhiteSpace($conversationId)) {
                $conversationId = 'subject:' + (Get-CleanSubject -Subject ([string]$item.Subject)).ToLowerInvariant()
            }

            $conversationIndex = ''
            try { $conversationIndex = [string]$item.ConversationIndex } catch {}

            $attachmentScan = Get-OutlookAttachmentMetadata -Item $item

            $messages += [ordered]@{
                direction = $Direction
                entryId = $entryId
                storeId = [string]$Folder.StoreID
                conversationId = $conversationId
                conversationIndex = $conversationIndex
                conversationTopic = Get-CleanSubject -Subject ([string]$item.ConversationTopic)
                subject = [string]$item.Subject
                sender = [string]$item.SenderName
                senderEmail = [string]$item.SenderEmailAddress
                recipients = [string]$item.To
                date = $date.ToUniversalTime().ToString('o')
                preview = Get-ShortMailBody -Item $item
                body = Get-MailBodyForScan -Item $item
                attachmentNames = @($attachmentScan.names)
                attachmentText = [string]$attachmentScan.text
                attachmentScan = @($attachmentScan.items)
                unread = [bool]$item.UnRead
            }

            if ($messages.Count -ge $MaxItems) { break }
        } catch {}
    }

    Write-Host "  [Outlook] $FolderLabel finished with $($messages.Count) message(s)." -ForegroundColor DarkCyan
    return $messages
}

function Save-OutlookMessage {
    param(
        [object]$Session,
        [object]$Message,
        [string]$Folder
    )

    $entryId = [string]$Message.entryId
    $storeId = [string]$Message.storeId
    if ([string]::IsNullOrWhiteSpace($entryId)) { return $null }

    $item = $null
    try {
        if ([string]::IsNullOrWhiteSpace($storeId)) {
            $item = $Session.GetItemFromID($entryId)
        } else {
            $item = $Session.GetItemFromID($entryId, $storeId)
        }
        if ($null -eq $item) { return $null }

        $direction = [string]$Message.direction
        $date = Get-OutlookItemDate -Item $item -Direction $direction
        if ($null -eq $date) {
            $date = Get-OutlookItemDate -Item $item -Direction 'inbox'
        }
        if ($null -eq $date) { $date = Get-Date }

        $safeName = Get-OutlookFileName -Item $item -Date $date
        $filePath = Get-UniqueFilePath $Folder $safeName
        $item.SaveAs($filePath, 3)
        $savedItem = Get-Item $filePath

        $conversationId = ''
        try { $conversationId = [string]$item.ConversationID } catch {}
        $conversationIndex = ''
        try { $conversationIndex = [string]$item.ConversationIndex } catch {}

        return [ordered]@{
            fileName = $savedItem.Name
            path = $null
            size = $savedItem.Length
            sentAt = $date.ToUniversalTime().ToString('o')
            name = $savedItem.Name
            subject = [string]$item.Subject
            entryId = $entryId
            conversationId = $conversationId
            conversationIndex = $conversationIndex
        }
    } catch {
        return $null
    } finally {
        if ($null -ne $item) {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($item) } catch {}
        }
    }
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  CFMA TASKA - Local Server" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Server running at http://localhost:$port/" -ForegroundColor Green
Write-Host ""
Write-Host "  Open this in your browser:" -ForegroundColor White
Write-Host "  http://localhost:$port/" -ForegroundColor Yellow
Write-Host "  App folder: $appRoot" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Keep this window open while using the toolbox." -ForegroundColor White
Write-Host "  Press Ctrl+C to stop the server." -ForegroundColor White
Write-Host ""

while ($listener.IsListening) {
    $ctx      = $listener.GetContext()
    $req      = $ctx.Request
    $res      = $ctx.Response
    $res.Headers.Add('Access-Control-Allow-Origin', '*')
    $res.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $res.Headers.Add('Access-Control-Allow-Private-Network', 'true')

    if ($req.HttpMethod -eq 'OPTIONS') {
        $res.StatusCode = 204
        $res.ContentLength64 = 0
        $res.OutputStream.Close()
        continue
    }

    $path = $req.Url.LocalPath.TrimStart('/')

    # ── Projects API ───────────────────────────────────────────────────────────
    if ($path -eq 'api/projects') {
        $projectsPath = Join-Path $root 'Projects'
        $items = @()
        if (Test-Path $projectsPath) {
            $items = Get-ChildItem $projectsPath -Filter '*.html' | Sort-Object Name | ForEach-Object {
                '{"name":"' + $_.BaseName + '","file":"Projects/' + $_.Name + '"}'
            }
        }
        $json = '[' + ($items -join ',') + ']'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentType = 'application/json; charset=utf-8'
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.OutputStream.Close()
        Write-Host "  [API] Projects listed ($($items.Count) files)" -ForegroundColor Cyan
        continue
    }

    # ── Auto-save API ─────────────────────────────────────────────────────────
    if ($path -eq 'api/open-folder') {
        try {
            $jobText = $req.QueryString['job']
            $jobNum = Get-JobNumber -JobText $jobText

            if ($null -eq $jobNum) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Enter a valid job number first.' }
                Write-Host "  [Explorer] Invalid job number" -ForegroundColor Yellow
                continue
            }

            $parent = [int]([math]::Floor($jobNum / 100) * 100)
            $folderPath = Join-Path (Join-Path 'S:\JOBS' ([string]$parent)) ([string]$jobNum)

            if (-not (Test-Path $folderPath -PathType Container)) {
                Write-JsonResponse $res 404 @{ ok = $false; error = 'Folder not found.'; path = $folderPath }
                Write-Host "  [Explorer] Folder not found: $folderPath" -ForegroundColor Yellow
                continue
            }

            Start-Process -FilePath explorer.exe -ArgumentList "`"$folderPath`""
            Write-JsonResponse $res 200 @{ ok = $true; path = $folderPath }
            Write-Host "  [Explorer] Opened $folderPath" -ForegroundColor Green
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not open folder.' }
            Write-Host "  [Explorer] Error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/save-job-email') {
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $jobNum = Get-JobNumber -JobText ($req.QueryString['job'])
            if ($null -eq $jobNum) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Enter a valid job number first.' }
                Write-Host "  [Email] Invalid job number" -ForegroundColor Yellow
                continue
            }

            $emailRoot = Get-AppFilePath 'Job Emails'
            $jobEmailFolder = Join-Path $emailRoot ([string]$jobNum)
            if (-not (Test-Path $jobEmailFolder)) {
                New-Item -ItemType Directory -Path $jobEmailFolder | Out-Null
            }

            $safeName = Get-SafeFileName -FileName ($req.QueryString['name'])
            $filePath = Get-UniqueFilePath $jobEmailFolder $safeName
            $fileStream = [System.IO.File]::Create($filePath)
            try {
                $req.InputStream.CopyTo($fileStream)
            } finally {
                $fileStream.Close()
            }

            $savedItem = Get-Item $filePath
            $relativePath = Get-AppRelativePath "Job Emails\$jobNum\$($savedItem.Name)"
            $sentAt = Get-EmailSentAt -FilePath $filePath
            Write-JsonResponse $res 200 @{
                ok = $true
                fileName = $savedItem.Name
                path = $relativePath
                size = $savedItem.Length
                sentAt = $sentAt
            }
            Write-Host "  [Email] Saved $($savedItem.Name) for job $jobNum" -ForegroundColor Green
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not save email.' }
            Write-Host "  [Email] Save error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/open-job-email') {
        try {
            $relativePath = $req.QueryString['file']
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing email file.' }
                continue
            }

            $emailRoot = [System.IO.Path]::GetFullPath((Get-AppFilePath 'Job Emails'))
            $filePath = Get-AppFilePath $relativePath
            $emailRootPrefix = $emailRoot.TrimEnd('\') + '\'

            if (($null -eq $filePath) -or (-not $filePath.StartsWith($emailRootPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
                Write-JsonResponse $res 403 @{ ok = $false; error = 'Email file must be inside Job Emails.' }
                Write-Host "  [Email] Rejected path: $relativePath" -ForegroundColor Yellow
                continue
            }

            if (-not (Test-Path $filePath -PathType Leaf)) {
                Write-JsonResponse $res 404 @{ ok = $false; error = 'Email file not found.' }
                Write-Host "  [Email] Missing: $filePath" -ForegroundColor Yellow
                continue
            }

            Start-Process -FilePath $filePath
            Write-JsonResponse $res 200 @{ ok = $true; path = $relativePath }
            Write-Host "  [Email] Opened $filePath" -ForegroundColor Green
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not open email.' }
            Write-Host "  [Email] Open error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/email-sent-date') {
        try {
            $relativePath = $req.QueryString['file']
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing email file.' }
                continue
            }

            $emailRoot = [System.IO.Path]::GetFullPath((Get-AppFilePath 'Job Emails'))
            $filePath = Get-AppFilePath $relativePath
            $emailRootPrefix = $emailRoot.TrimEnd('\') + '\'

            if (($null -eq $filePath) -or (-not $filePath.StartsWith($emailRootPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
                Write-JsonResponse $res 403 @{ ok = $false; error = 'Email file must be inside Job Emails.' }
                Write-Host "  [Email] Rejected sent-date path: $relativePath" -ForegroundColor Yellow
                continue
            }

            if (-not (Test-Path $filePath -PathType Leaf)) {
                Write-JsonResponse $res 404 @{ ok = $false; error = 'Email file not found.' }
                Write-Host "  [Email] Missing for sent-date scan: $filePath" -ForegroundColor Yellow
                continue
            }

            $sentAt = Get-EmailSentAt -FilePath $filePath
            Write-JsonResponse $res 200 @{ ok = $true; sentAt = $sentAt }
            if ($sentAt) {
                Write-Host "  [Email] Read sent date for $filePath" -ForegroundColor Green
            } else {
                Write-Host "  [Email] No sent date found for $filePath" -ForegroundColor Yellow
            }
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not read email sent date.' }
            Write-Host "  [Email] Sent-date error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/ai-status') {
        try {
            if ($req.HttpMethod -ne 'GET') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'GET required.' }
                continue
            }

            $api = Get-OpenAiApiKey
            Write-JsonResponse $res 200 @{
                ok = $true
                configured = -not [string]::IsNullOrWhiteSpace($api.key)
                source = $api.source
                model = Get-OpenAiModel
            }
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not read AI status.' }
        }
        continue
    }

    if ($path -eq 'api/save-openai-key') {
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $payload = Read-JsonRequestBody -Request $req
            if ($null -eq $payload) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing request body.' }
                continue
            }

            $apiKey = ConvertTo-SafeAiText $payload.apiKey 300
            $model = ConvertTo-SafeAiText $payload.model 80
            if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey.Length -lt 20) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Paste a valid OpenAI API key.' }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($model)) { $model = Get-OpenAiModel }

            $secrets = Get-TimewrapSecrets
            if ($null -eq $secrets -or $secrets -isnot [System.Collections.IDictionary]) {
                $secrets = [ordered]@{}
            }
            $secrets['openaiApiKey'] = $apiKey
            $secrets['openaiModel'] = $model
            Save-TimewrapSecrets -Secrets $secrets

            Write-JsonResponse $res 200 @{ ok = $true; configured = $true; model = $model }
            Write-Host "  [AI] OpenAI key saved locally" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            Write-JsonResponse $res 500 @{ ok = $false; error = "Could not save OpenAI key. $detail" }
            Write-Host "  [AI] Save key error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/clear-openai-key') {
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $secrets = Get-TimewrapSecrets
            if ($null -ne $secrets -and $secrets -is [System.Collections.IDictionary] -and $secrets.Contains('openaiApiKey')) {
                $secrets.Remove('openaiApiKey')
            }
            Save-TimewrapSecrets -Secrets $secrets
            Write-JsonResponse $res 200 @{ ok = $true; configured = $false }
            Write-Host "  [AI] Local OpenAI key cleared" -ForegroundColor Yellow
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not clear OpenAI key.' }
        }
        continue
    }

    if ($path -eq 'api/ai-outlook-triage') {
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $payload = Read-JsonRequestBody -Request $req
            if ($null -eq $payload) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing request body.' }
                continue
            }

            $groups = Get-OutlookAiGroupsFromPayload -Payload $payload
            Write-Host "  [AI] Outlook triage request received for $($groups.Count) conversation(s)" -ForegroundColor Cyan
            if ($groups.Count -eq 0) {
                Write-JsonResponse $res 200 @{
                    ok = $true
                    configured = $true
                    model = Get-OpenAiModel
                    items = @()
                    usedGroups = 0
                }
                continue
            }

            $aiResult = Invoke-TimewrapOutlookTriage -Payload $payload
            Write-JsonResponse $res 200 @{
                ok = $true
                configured = $true
                model = Get-OpenAiModel
                items = @($aiResult.items)
                usedGroups = $groups.Count
            }
            Write-Host "  [AI] Triaged $($groups.Count) Outlook conversation(s)" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            $status = if ($detail -match 'not configured') { 503 } else { 500 }
            Write-JsonResponse $res $status @{ ok = $false; configured = $false; error = $detail }
            Write-Host "  [AI] Outlook triage error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/ai-weekly-briefing') {
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $payload = Read-JsonRequestBody -Request $req
            if ($null -eq $payload) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing request body.' }
                continue
            }

            Write-Host "  [AI] Weekly briefing request received" -ForegroundColor Cyan
            $aiResult = Invoke-TimewrapWeeklyBriefing -Payload $payload
            Write-JsonResponse $res 200 @{
                ok = $true
                configured = $true
                model = Get-OpenAiModel
                briefing = $aiResult
            }
            Write-Host "  [AI] Weekly briefing generated" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            $status = if ($detail -match 'not configured') { 503 } else { 500 }
            Write-JsonResponse $res $status @{ ok = $false; configured = $false; error = $detail }
            Write-Host "  [AI] Weekly briefing error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/ai-email-extract') {
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $payload = Read-JsonRequestBody -Request $req
            if ($null -eq $payload) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing request body.' }
                continue
            }

            $groups = Get-AiEmailGroups -Payload $payload
            if ($groups.emails.Count -eq 0) {
                Write-JsonResponse $res 200 @{
                    ok = $true
                    configured = $true
                    model = Get-OpenAiModel
                    items = @()
                    usedGroups = 0
                    totalGroups = 0
                }
                continue
            }

            $aiResult = Invoke-TimewrapOpenAiExtraction -Payload $payload -Emails $groups.emails
            $items = Convert-AiExtractionToCalendarItems -AiResult $aiResult -GroupLookup $groups.lookup
            Write-JsonResponse $res 200 @{
                ok = $true
                configured = $true
                model = Get-OpenAiModel
                items = @($items)
                usedGroups = $groups.emails.Count
                totalGroups = $groups.totalGroups
            }
            Write-Host "  [AI] Extracted $($items.Count) Gmail calendar items from $($groups.emails.Count) thread groups" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            $status = if ($detail -match 'not configured') { 503 } else { 500 }
            Write-JsonResponse $res $status @{ ok = $false; configured = $false; error = $detail }
            Write-Host "  [AI] Extraction error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/scan-gmail-script') {
        try {
            if ($req.HttpMethod -ne 'GET') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'GET required.' }
                continue
            }

            $scriptUrl = [string]$req.QueryString['url']
            if ([string]::IsNullOrWhiteSpace($scriptUrl)) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing Gmail Apps Script URL.' }
                continue
            }
            $scriptToken = [string]$req.QueryString['token']
            if ([string]::IsNullOrWhiteSpace($scriptToken)) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing Gmail scanner token.' }
                continue
            }

            [System.Uri]$uri = $null
            if (-not [System.Uri]::TryCreate($scriptUrl, [System.UriKind]::Absolute, [ref]$uri)) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Invalid Gmail Apps Script URL.' }
                continue
            }

            $allowedHosts = @('script.google.com', 'script.googleusercontent.com')
            if ($uri.Scheme -ne 'https' -or -not ($allowedHosts -contains $uri.Host.ToLowerInvariant())) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Gmail URL must be a Google Apps Script web app URL.' }
                continue
            }

            $separator = if ([string]::IsNullOrEmpty($uri.Query)) { '?' } else { '&' }
            $scanUrl = $uri.AbsoluteUri + $separator + 'token=' + [System.Uri]::EscapeDataString($scriptToken)

            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (compatible; SurveyorsToolbox/1.0)')
            $json = $wc.DownloadString($scanUrl)
            try {
                $null = $json | ConvertFrom-Json
            } catch {
                throw 'The Gmail Apps Script did not return JSON. Check that it is deployed as a web app.'
            }

            Write-TextResponse $res 200 'application/json; charset=utf-8' $json
            Write-Host "  [Gmail] Scanned via Apps Script" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            Write-JsonResponse $res 500 @{ ok = $false; error = "Could not scan Gmail. $detail" }
            Write-Host "  [Gmail] Scan error: $_" -ForegroundColor Red
        }
        continue
    }

    if ($path -eq 'api/scan-outlook-emails') {
        $outlook = $null
        $namespace = $null
        $inbox = $null
        $sent = $null
        try {
            if ($req.HttpMethod -ne 'GET') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'GET required.' }
                continue
            }

            $sinceRaw = [string]$req.QueryString['since']
            if ([string]::IsNullOrWhiteSpace($sinceRaw)) {
                Write-Host "  [Outlook] Scan request received (last 2 weeks)." -ForegroundColor Cyan
            } else {
                Write-Host "  [Outlook] Scan request received since $sinceRaw." -ForegroundColor Cyan
            }

            $outlook = Get-RunningOutlookApplication
            if ($null -eq $outlook) {
                Write-JsonResponse $res 503 @{ ok = $false; error = 'Open Outlook first, then scan again.' }
                Write-Host "  [Outlook] Outlook desktop COM app not found. Open classic Outlook, then scan again." -ForegroundColor Yellow
                continue
            }

            $startDate = Get-ScanStartDate -Since $sinceRaw
            try {
                $namespace = $outlook.Session
            } catch {
                Write-Host "  [Outlook] Mail session could not be accessed: $($_.Exception.Message)" -ForegroundColor Yellow
                throw "Outlook is open, but its mail session could not be accessed. $($_.Exception.Message)"
            }

            $messages = @()
            $scanErrors = @()

            try {
                $inbox = $namespace.GetDefaultFolder(6)
                $messages += Get-OutlookFolderMessages -Folder $inbox -Direction 'inbox' -StartDate $startDate -MaxItems $OutlookScanMaxItemsPerFolder -FolderLabel 'Inbox'
            } catch {
                $scanErrors += "Inbox: $($_.Exception.Message)"
            }

            try {
                $sent = $namespace.GetDefaultFolder(5)
                $messages += Get-OutlookFolderMessages -Folder $sent -Direction 'sent' -StartDate $startDate -MaxItems $OutlookScanMaxItemsPerFolder -FolderLabel 'Sent Items'
            } catch {
                $scanErrors += "Sent Items: $($_.Exception.Message)"
            }

            if ($messages.Count -eq 0 -and $scanErrors.Count -gt 0) {
                Write-Host "  [Outlook] Folder read errors: $($scanErrors -join ' ')" -ForegroundColor Yellow
                throw "Could not read Outlook folders. $($scanErrors -join ' ')"
            }

            Write-JsonResponse $res 200 @{
                ok = $true
                scannedAt = (Get-Date).ToUniversalTime().ToString('o')
                since = $startDate.ToUniversalTime().ToString('o')
                messages = @($messages)
                warnings = @($scanErrors)
            }
            Write-Host "  [Outlook] Scanned $($messages.Count) messages since $startDate" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            Write-JsonResponse $res 500 @{ ok = $false; error = "Could not scan Outlook. $detail" }
            Write-Host "  [Outlook] Scan error: $_" -ForegroundColor Red
        } finally {
            foreach ($obj in @($sent, $inbox, $namespace)) {
                if ($null -ne $obj) {
                    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
                }
            }
        }
        continue
    }

    if ($path -eq 'api/open-outlook-email') {
        $outlook = $null
        $namespace = $null
        $item = $null
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $payload = Read-JsonRequestBody -Request $req
            if ($null -eq $payload) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing request body.' }
                continue
            }

            $entryId = [string]$payload.entryId
            $storeId = [string]$payload.storeId
            if ([string]::IsNullOrWhiteSpace($entryId)) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing Outlook message id.' }
                continue
            }

            $outlook = Get-RunningOutlookApplication
            if ($null -eq $outlook) {
                Write-JsonResponse $res 503 @{ ok = $false; error = 'Open Outlook first, then try again.' }
                continue
            }

            $namespace = $outlook.Session
            if ([string]::IsNullOrWhiteSpace($storeId)) {
                $item = $namespace.GetItemFromID($entryId)
            } else {
                $item = $namespace.GetItemFromID($entryId, $storeId)
            }
            if ($null -eq $item) {
                Write-JsonResponse $res 404 @{ ok = $false; error = 'Could not find that Outlook email.' }
                continue
            }

            $item.Display()
            Write-JsonResponse $res 200 @{ ok = $true }
            Write-Host "  [Outlook] Opened preview email" -ForegroundColor Green
        } catch {
            $detail = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
            Write-JsonResponse $res 500 @{ ok = $false; error = "Could not open Outlook email. $detail" }
            Write-Host "  [Outlook] Open preview error: $_" -ForegroundColor Red
        } finally {
            foreach ($obj in @($item, $namespace)) {
                if ($null -ne $obj) {
                    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
                }
            }
        }
        continue
    }

    if ($path -eq 'api/save-outlook-emails') {
        $outlook = $null
        $namespace = $null
        try {
            if ($req.HttpMethod -ne 'POST') {
                Write-JsonResponse $res 405 @{ ok = $false; error = 'POST required.' }
                continue
            }

            $payload = Read-JsonRequestBody -Request $req
            if ($null -eq $payload) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Missing request body.' }
                continue
            }

            $jobNum = Get-JobNumber -JobText ([string]$payload.job)
            if ($null -eq $jobNum) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'Select a job with a valid job number first.' }
                continue
            }

            $messageList = @()
            if ($null -ne $payload.messages) { $messageList = @($payload.messages) }
            if ($messageList.Count -eq 0) {
                Write-JsonResponse $res 400 @{ ok = $false; error = 'No Outlook messages selected.' }
                continue
            }

            $outlook = Get-RunningOutlookApplication
            if ($null -eq $outlook) {
                Write-JsonResponse $res 503 @{ ok = $false; error = 'Open Outlook first, then try again.' }
                continue
            }

            $emailRoot = Get-AppFilePath 'Job Emails'
            $jobEmailFolder = Join-Path $emailRoot ([string]$jobNum)
            if (-not (Test-Path $jobEmailFolder)) {
                New-Item -ItemType Directory -Path $jobEmailFolder | Out-Null
            }

            $namespace = $outlook.Session
            $saved = @()
            foreach ($message in $messageList) {
                $mail = Save-OutlookMessage -Session $namespace -Message $message -Folder $jobEmailFolder
                if ($null -ne $mail) {
                    $mail['path'] = Get-AppRelativePath "Job Emails\$jobNum\$($mail.fileName)"
                    $saved += $mail
                }
            }

            if ($saved.Count -eq 0) {
                Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not save any selected Outlook emails.' }
                continue
            }

            Write-JsonResponse $res 200 @{
                ok = $true
                emails = @($saved)
            }
            Write-Host "  [Outlook] Saved $($saved.Count) message(s) for job $jobNum" -ForegroundColor Green
        } catch {
            Write-JsonResponse $res 500 @{ ok = $false; error = 'Could not save Outlook emails.' }
            Write-Host "  [Outlook] Save error: $_" -ForegroundColor Red
        } finally {
            if ($null -ne $namespace) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($namespace) } catch {}
            }
        }
        continue
    }

    if ($path -eq 'api/autosave') {
        try {
            $backupsPath = Get-AppFilePath 'Backups'
            if (-not (Test-Path $backupsPath)) { New-Item -ItemType Directory -Path $backupsPath | Out-Null }
            $reader = New-Object System.IO.StreamReader($req.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $dateStr = Get-Date -Format 'yyyy-MM-dd'
            $fileName = "autosave-$dateStr.json"
            $filePath = Join-Path $backupsPath $fileName
            [System.IO.File]::WriteAllText($filePath, $body, [System.Text.Encoding]::UTF8)
            $ok = '{"ok":true}'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($ok)
            $res.ContentType = 'application/json'
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "  [Backup] Saved $fileName" -ForegroundColor Green
        } catch {
            $err = '{"ok":false}'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($err)
            $res.StatusCode = 500
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "  [Backup] Error: $_" -ForegroundColor Red
        }
        $res.OutputStream.Close()
        continue
    }

    # ── ICS Proxy ──────────────────────────────────────────────────────────────
    if ($path -eq 'ics-proxy') {
        $icsUrl = $req.QueryString['url']
        if ($icsUrl) {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (compatible; SurveyorsToolbox/1.0)')
                $icsContent = $wc.DownloadString($icsUrl)
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($icsContent)
                $res.ContentType = 'text/calendar; charset=utf-8'
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "  [ICS] Fetched calendar OK" -ForegroundColor Green
            } catch {
                $errMsg = "Error fetching ICS: $_"
                Write-Host "  [ICS] $errMsg" -ForegroundColor Red
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                $res.StatusCode = 500
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        } else {
            $res.StatusCode = 400
        }
        $res.OutputStream.Close()
        continue
    }

    # ── Static File Serving ───────────────────────────────────────────────────
    if ($path -eq '' -or $path -eq 'index.html') { $path = 'surveyors-toolbox.html' }
    $file = Get-AppFilePath $path

    if (($null -ne $file) -and (Test-Path $file -PathType Leaf)) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $res.ContentType = switch -Regex ($file) {
            '\.html$' { 'text/html; charset=utf-8' }
            '\.css$'  { 'text/css' }
            '\.js$'   { 'application/javascript' }
            '\.json$' { 'application/json' }
            '\.png$'  { 'image/png' }
            '\.jpg$'  { 'image/jpeg' }
            '\.ico$'  { 'image/x-icon' }
            default   { 'application/octet-stream' }
        }
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $notFound = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
        $res.StatusCode = 404
        $res.ContentLength64 = $notFound.Length
        $res.OutputStream.Write($notFound, 0, $notFound.Length)
    }

    $res.OutputStream.Close()
}
