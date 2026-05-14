/*
  Gmail scanner for CFMA TASKA.

  This version uses the Advanced Gmail API, not GmailApp, so the manifest can
  request only:
    https://www.googleapis.com/auth/gmail.readonly

  Apps Script setup:
  1. Paste this file into Code.gs.
  2. In Services, add "Gmail API".
  3. In Project Settings, show appsscript.json and set it to the manifest in
     gmail-scanner-appsscript-manifest.json.
  4. Deploy as a Web App.
  5. In the toolbox Gmail Setup, paste the web app URL and this token:
     Id6IE1tSk8wb5vcxVZ1AaEEp04LBvO2tgzqJouW8lNo
*/

const LOOKBACK_DAYS = 31;
const MAX_MESSAGES = 320;
const MAX_THREADS = 180;
const MAX_MESSAGES_PER_PAGE = 100;
const MAX_PAGES_PER_QUERY = 5;
const MAX_BODY_CHARS = 12000;
const MAX_HTML_CHARS = 24000;
const MAX_ATTACHMENT_BYTES = 6 * 1024 * 1024;
const MAX_ATTACHMENT_CHARS = 12000;
const MAX_ATTACHMENTS_PER_MESSAGE = 8;
const TOOLBOX_GMAIL_TOKEN = 'Id6IE1tSk8wb5vcxVZ1AaEEp04LBvO2tgzqJouW8lNo';

function doGet(e) {
  const providedToken = String((e && e.parameter && e.parameter.token) || '');
  if (!TOOLBOX_GMAIL_TOKEN || providedToken !== TOOLBOX_GMAIL_TOKEN) {
    return jsonResponse({
      ok: false,
      error: 'Invalid Gmail scanner token.'
    });
  }

  const start = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000);
  const queries = [
    // Start with the recent inbox so useful non-Primary mail is not missed.
    // Targeted queries below make sure bills/bookings are found even when the
    // general inbox page is full of lower-value updates.
    { label: 'primary', q: 'newer_than:31d in:inbox category:primary -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "reservation confirmed" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "booking confirmed" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "confirmed booking" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "confirmed reservation" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "reservation is confirmed" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "booking is confirmed" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb reservation confirmed -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb booking confirmed -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb nights -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "request to book" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb requested -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "guest arrives" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb arrives -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "guest arriving" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "check-in" -in:spam -in:trash' },
    { label: 'airbnb', q: 'newer_than:31d in:inbox airbnb "start date" -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox qldc -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox rates -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox "Queenstown Lakes" -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox "Queenstown Lakes District Council" -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox "quarterly rates invoice" -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox "rates invoice" -in:spam -in:trash' },
    { label: 'rates', q: 'newer_than:31d in:inbox "now due" rates -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox power -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox electricity -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox energy bill -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "Contact Energy" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox contact "latest bill" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "your latest bill" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "what do I owe" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "what do i owe" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "amount due" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "payment due" -in:spam -in:trash' },
    { label: 'power', q: 'newer_than:31d in:inbox "amount owing" -in:spam -in:trash' },
    { label: 'bills', q: 'newer_than:31d in:inbox invoice -in:spam -in:trash' },
    { label: 'bills', q: 'newer_than:31d in:inbox bill -in:spam -in:trash' },
    { label: 'paid', q: 'newer_than:31d in:inbox paid -in:spam -in:trash' },
    { label: 'paid', q: 'newer_than:31d in:inbox receipt -in:spam -in:trash' },
    { label: 'paid', q: 'newer_than:31d in:inbox confirmation -in:spam -in:trash' },
    { label: 'paid', q: 'newer_than:31d in:inbox "payment confirmation" -in:spam -in:trash' },
    { label: 'accountant', q: 'newer_than:31d in:inbox accountant -in:spam -in:trash' },
    { label: 'accountant', q: 'newer_than:31d in:inbox accounting -in:spam -in:trash' },
    { label: 'accountant', q: 'newer_than:31d in:inbox tax -in:spam -in:trash' },
    { label: 'accountant', q: 'newer_than:31d in:inbox gst -in:spam -in:trash' },
    { label: 'accountant', q: 'newer_than:31d in:inbox ird -in:spam -in:trash' },
    { label: 'accountant', q: 'newer_than:31d in:inbox cross -in:spam -in:trash' },
    { label: 'appointments', q: 'newer_than:31d in:inbox appointment -in:spam -in:trash' },
    { label: 'appointments', q: 'newer_than:31d in:inbox doctor -in:spam -in:trash' },
    { label: 'appointments', q: 'newer_than:31d in:inbox dentist -in:spam -in:trash' },
    { label: 'appointments', q: 'newer_than:31d in:inbox clinic -in:spam -in:trash' },
    { label: 'inbox', q: 'newer_than:31d in:inbox -in:spam -in:trash' }
  ];
  const seenIds = {};
  const messages = [];

  queries.forEach(spec => {
    listMessagesForQuery(spec, start, seenIds, messages);
  });

  messages.sort((a, b) => new Date(b.date) - new Date(a.date));
  const threadMessages = dedupeMessagesByThread(messages).slice(0, MAX_THREADS);
  return jsonResponse({
    ok: true,
    scannedAt: new Date().toISOString(),
    lookbackDays: LOOKBACK_DAYS,
    fetchedMessages: messages.length,
    returnedThreads: threadMessages.length,
    messages: threadMessages
  });
}

function listMessagesForQuery(spec, start, seenIds, messages) {
  if (messages.length >= MAX_MESSAGES) return;
  let pageToken = '';
  let page = 0;
  do {
    const params = {
      q: spec.q,
      maxResults: MAX_MESSAGES_PER_PAGE
    };
    if (pageToken) params.pageToken = pageToken;

    const listed = Gmail.Users.Messages.list('me', params);
    (listed.messages || []).forEach(item => {
      if (!item.id || seenIds[item.id]) return;
      seenIds[item.id] = true;
      if (messages.length >= MAX_MESSAGES) return;

      const message = readMessage(item, start, spec.label);
      if (message) messages.push(message);
    });

    pageToken = listed.nextPageToken || '';
    page++;
  } while (pageToken && page < MAX_PAGES_PER_QUERY && messages.length < MAX_MESSAGES);
}

function readMessage(item, start, sourceLabel) {
  try {
    const message = Gmail.Users.Messages.get('me', item.id, {
      format: 'full'
    });
    const date = message.internalDate
      ? new Date(Number(message.internalDate))
      : headerDate(message);
    if (!date || date < start) return null;

    const attachmentInfos = collectAttachmentInfo(message.payload || {});
    const attachmentNames = attachmentInfos.map(item => item.name).filter(Boolean);
    const scannedAttachments = scanGmailAttachments(message.id, attachmentInfos);
    const attachments = attachmentInfos.map((info, index) => {
      const scan = scannedAttachments[index] || {};
      return {
        name: info.name || '',
        mimeType: info.mimeType || '',
        size: info.size || 0,
        scanned: !!scan.scanned,
        kind: scan.kind || 'metadata',
        chars: scan.chars || 0,
        error: scan.error || ''
      };
    });
    const attachmentText = cleanText(scannedAttachments.map(item => item.text || '').join(' ')).slice(0, MAX_ATTACHMENT_CHARS);
    const subject = headerValue(message, 'Subject');
    const from = headerValue(message, 'From');
    const to = headerValue(message, 'To');
    const sender = parseAddressHeader(from);
    const bodyParts = messageBodies(message);
    const plainTextBody = cleanText(bodyParts.plainText).slice(0, MAX_BODY_CHARS);
    const htmlBody = String(bodyParts.html || '').slice(0, MAX_HTML_CHARS);
    const cleanedHtmlText = cleanText(stripHtml(htmlBody)).slice(0, MAX_BODY_CHARS);
    const cleanedBodyText = cleanText([plainTextBody || cleanedHtmlText, attachmentNames.join(' ')].join(' ')).slice(0, MAX_BODY_CHARS);
    const airbnbText = cleanText([subject, from, to, message.snippet, cleanedBodyText, attachmentText].join(' ')).toLowerCase();
    const threadText = sourceLabel === 'airbnb' || airbnbText.indexOf('airbnb') !== -1
      ? readThreadText(message.threadId)
      : '';
    const labels = message.labelIds || [];
    return {
      id: message.id,
      threadId: message.threadId,
      provider: 'gmail',
      date: date.toISOString(),
      receivedAt: date.toISOString(),
      subject,
      fromName: sender.name,
      fromEmail: sender.email,
      from,
      to,
      source: sourceLabel || 'primary',
      labels,
      attachments,
      attachmentNames,
      attachmentText,
      threadText,
      snippet: cleanText(message.snippet || cleanedBodyText).slice(0, 700),
      plainTextBody,
      cleanedBodyText,
      htmlBody,
      body: cleanedBodyText,
      sourceUrl: gmailMessageUrl(message),
      rawMetadata: {
        id: message.id,
        threadId: message.threadId,
        historyId: message.historyId || '',
        sizeEstimate: message.sizeEstimate || 0,
        labels
      }
    };
  } catch (e) {
    return null;
  }
}

function dedupeMessagesByThread(messages) {
  const groups = {};
  const order = [];
  messages.forEach(message => {
    const key = message.threadId || message.id;
    if (!key) return;
    if (!groups[key]) {
      groups[key] = [];
      order.push(key);
    }
    groups[key].push(message);
  });

  return order.map(key => {
    const group = groups[key].sort((a, b) => new Date(b.date) - new Date(a.date));
    const primary = group[0];
    primary.threadMessageIds = group.map(item => item.id).filter(Boolean);
    primary.threadMessageCount = group.length;
    primary.sources = uniqueValues(group.map(item => item.source).filter(Boolean));
    if (!primary.threadText && group.length > 1) {
      primary.threadText = cleanText(group.map(item => [
        item.subject,
        item.from,
        item.snippet,
        item.cleanedBodyText || item.body || ''
      ].filter(Boolean).join(' ')).join(' ')).slice(0, MAX_BODY_CHARS);
    }
    return primary;
  }).sort((a, b) => new Date(b.date) - new Date(a.date));
}

function uniqueValues(values) {
  const seen = {};
  const out = [];
  values.forEach(value => {
    const key = String(value || '');
    if (!key || seen[key]) return;
    seen[key] = true;
    out.push(key);
  });
  return out;
}

function gmailMessageUrl(message) {
  const key = (message && (message.threadId || message.id)) || '';
  return key ? 'https://mail.google.com/mail/u/0/#inbox/' + encodeURIComponent(key) : '';
}

function parseAddressHeader(value) {
  const raw = String(value || '').trim();
  const emailMatch = raw.match(/<([^>]+)>/) || raw.match(/([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})/i);
  const email = emailMatch ? String(emailMatch[1] || emailMatch[0]).trim().toLowerCase() : '';
  let name = raw.replace(/<[^>]+>/g, '').replace(/["']/g, '').trim();
  if (!name && email) name = email.split('@')[0].replace(/[._-]+/g, ' ');
  return { name, email };
}

function readThreadText(threadId) {
  if (!threadId) return '';
  try {
    const thread = Gmail.Users.Threads.get('me', threadId, {
      format: 'full'
    });
    return cleanText(((thread && thread.messages) || []).slice(-10).map(message => {
      const payload = message.payload || {};
      const attachmentNames = collectAttachmentInfo(payload).map(item => item.name).filter(Boolean).join(' ');
      return [
        headerValue(message, 'Subject'),
        headerValue(message, 'From'),
        headerValue(message, 'To'),
        message.snippet || '',
        messageText(message),
        attachmentNames
      ].filter(Boolean).join(' ');
    }).join(' ')).slice(0, MAX_BODY_CHARS);
  } catch (e) {
    return '';
  }
}

function jsonResponse(body) {
  return ContentService
    .createTextOutput(JSON.stringify(body))
    .setMimeType(ContentService.MimeType.JSON);
}

function headerValue(message, name) {
  const headers = (message.payload && message.payload.headers) || [];
  const found = headers.find(h => String(h.name || '').toLowerCase() === name.toLowerCase());
  return found ? String(found.value || '') : '';
}

function headerDate(message) {
  const raw = headerValue(message, 'Date');
  if (!raw) return null;
  const date = new Date(raw);
  return isNaN(date.getTime()) ? null : date;
}

function messageText(message) {
  const bodies = messageBodies(message);
  return bodies.plainText || stripHtml(bodies.html);
}

function messageBodies(message) {
  const out = { plainText: '', html: '' };
  collectPayloadBodies((message && message.payload) || {}, out);
  return out;
}

function collectPayloadBodies(part, out) {
  if (!part) return out;
  const mimeType = String(part.mimeType || '').toLowerCase();
  const filename = String(part.filename || '');

  if (!filename && part.body && part.body.data) {
    const decoded = decodeBody(part.body.data);
    if (mimeType === 'text/plain') out.plainText += decoded + ' ';
    if (mimeType === 'text/html') out.html += decoded + ' ';
  }

  (part.parts || []).forEach(child => {
    collectPayloadBodies(child, out);
  });

  return out;
}

function collectAttachmentInfo(part, list) {
  if (!list) list = [];
  if (!part) return list;
  const filename = String(part.filename || '').trim();
  if (filename) {
    list.push({
      name: filename,
      mimeType: String(part.mimeType || ''),
      attachmentId: part.body && part.body.attachmentId ? String(part.body.attachmentId) : '',
      data: part.body && part.body.data ? String(part.body.data) : '',
      size: part.body && part.body.size ? Number(part.body.size) : 0
    });
  }
  (part.parts || []).forEach(child => {
    collectAttachmentInfo(child, list);
  });
  return list;
}

function scanGmailAttachments(messageId, attachmentInfos) {
  return (attachmentInfos || []).slice(0, MAX_ATTACHMENTS_PER_MESSAGE).map(info => {
    const result = {
      name: info.name || 'attachment',
      size: info.size || 0,
      scanned: false,
      kind: 'unsupported',
      chars: 0,
      error: '',
      text: ''
    };

    if (result.size > MAX_ATTACHMENT_BYTES) {
      result.kind = 'too-large';
      result.error = 'Skipped large attachment.';
      return result;
    }

    try {
      const read = readGmailAttachmentText(messageId, info);
      result.kind = read.kind || result.kind;
      result.text = cleanText(read.text || '').slice(0, MAX_ATTACHMENT_CHARS);
      result.scanned = !!result.text;
      result.chars = result.text.length;
    } catch (e) {
      result.kind = 'error';
      result.error = 'Could not scan attachment.';
    }

    return result;
  });
}

function readGmailAttachmentText(messageId, info) {
  const ext = attachmentExtension(info.name);
  const mimeType = String(info.mimeType || '').toLowerCase();
  const textLike = ['.txt', '.csv', '.tsv', '.ics', '.json', '.log'].indexOf(ext) >= 0 || mimeType.indexOf('text/') === 0;
  const htmlLike = ['.html', '.htm', '.xml'].indexOf(ext) >= 0 || mimeType.indexOf('html') >= 0 || mimeType.indexOf('xml') >= 0;
  const supported = textLike || htmlLike || ext === '.docx' || ext === '.xlsx' || ext === '.pdf';
  if (!supported) return { text: '', kind: 'unsupported' };

  const bytes = gmailAttachmentBytes(messageId, info);
  if (!bytes || !bytes.length) return { text: '', kind: 'empty' };
  if (bytes.length > MAX_ATTACHMENT_BYTES) return { text: '', kind: 'too-large' };

  const blob = Utilities.newBlob(bytes, info.mimeType || 'application/octet-stream', info.name || 'attachment');
  if (textLike) return { text: blobToString(blob), kind: 'text' };
  if (htmlLike) return { text: stripHtml(blobToString(blob)), kind: 'html' };
  if (ext === '.docx') return { text: unzipXmlText(blob, [/^word\/document\.xml$/i, /^word\/header\d*\.xml$/i, /^word\/footer\d*\.xml$/i]), kind: 'docx' };
  if (ext === '.xlsx') return { text: unzipXmlText(blob, [/^xl\/sharedStrings\.xml$/i, /^xl\/worksheets\/.+\.xml$/i]), kind: 'xlsx' };
  if (ext === '.pdf') return { text: rawPdfText(blob), kind: 'pdf-raw' };
  return { text: '', kind: 'unsupported' };
}

function gmailAttachmentBytes(messageId, info) {
  if (info.data) return Utilities.base64DecodeWebSafe(info.data);
  if (!info.attachmentId) return [];
  const attachment = Gmail.Users.Messages.Attachments.get('me', messageId, info.attachmentId);
  return attachment && attachment.data ? Utilities.base64DecodeWebSafe(attachment.data) : [];
}

function attachmentExtension(name) {
  const m = String(name || '').toLowerCase().match(/(\.[a-z0-9]+)$/);
  return m ? m[1] : '';
}

function blobToString(blob) {
  try {
    return blob.getDataAsString('UTF-8');
  } catch (e) {
    try { return blob.getDataAsString(); } catch (_) { return ''; }
  }
}

function unzipXmlText(blob, patterns) {
  try {
    let text = '';
    Utilities.unzip(blob).forEach(file => {
      const name = file.getName();
      if (patterns.some(pattern => pattern.test(name))) {
        text += ' ' + file.getDataAsString('UTF-8');
      }
    });
    return stripXml(text);
  } catch (e) {
    return '';
  }
}

function stripXml(value) {
  return decodeHtmlEntities(String(value || '').replace(/<[^>]+>/g, ' '));
}

function rawPdfText(blob) {
  let raw = '';
  try {
    raw = blob.getDataAsString('ISO-8859-1');
  } catch (e) {
    raw = blobToString(blob);
  }
  const pieces = [];
  const matches = String(raw || '').match(/\((?:\\.|[^\\)]){4,}\)/g) || [];
  matches.some(match => {
    let value = match.slice(1, -1)
      .replace(/\\\(/g, '(')
      .replace(/\\\)/g, ')')
      .replace(/\\n|\\r|\\t/g, ' ');
    if (/[A-Za-z]{3,}/.test(value)) pieces.push(value);
    return pieces.join(' ').length > MAX_ATTACHMENT_CHARS;
  });
  return pieces.join(' ');
}

function decodeBody(data) {
  try {
    const bytes = Utilities.base64DecodeWebSafe(data);
    return Utilities.newBlob(bytes).getDataAsString('UTF-8');
  } catch (e) {
    return '';
  }
}

function stripHtml(value) {
  return decodeHtmlEntities(String(value || '')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<(br|\/p|\/div|\/li|\/tr|\/h[1-6])\b[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' '));
}

function cleanText(value) {
  return decodeHtmlEntities(String(value || ''))
    .replace(/\r?\n/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeHtmlEntities(value) {
  return String(value || '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&apos;/gi, "'")
    .replace(/&ndash;|&mdash;/gi, '-')
    .replace(/&rsquo;|&lsquo;/gi, "'")
    .replace(/&rdquo;|&ldquo;/gi, '"')
    .replace(/&#x([0-9a-f]+);/gi, function(_, code) {
      return String.fromCharCode(parseInt(code, 16));
    })
    .replace(/&#(\d+);/g, function(_, code) {
      return String.fromCharCode(Number(code));
    });
}
