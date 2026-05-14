(function(root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.TimewrapGmailAnalysis = factory();
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  const DEFAULT_TIMEZONE = 'Pacific/Auckland';
  const MS_DAY = 86400000;
  const MONTH_INDEX = {
    jan: 0, january: 0,
    feb: 1, february: 1,
    mar: 2, march: 2,
    apr: 3, april: 3,
    may: 4,
    jun: 5, june: 5,
    jul: 6, july: 6,
    aug: 7, august: 7,
    sep: 8, sept: 8, september: 8,
    oct: 9, october: 9,
    nov: 10, november: 10,
    dec: 11, december: 11
  };
  const WEEKDAY_INDEX = {
    sunday: 0, sun: 0,
    monday: 1, mon: 1,
    tuesday: 2, tue: 2, tues: 2,
    wednesday: 3, wed: 3,
    thursday: 4, thu: 4, thur: 4, thurs: 4,
    friday: 5, fri: 5,
    saturday: 6, sat: 6
  };

  const CATEGORY_RULES = [
    { category: 'bill', dateType: 'bill_due', score: 4, reason: 'billing or invoice language', re: /\b(invoice|amount due|payment due|overdue|statement|bill|balance due|total due|amount owing|pay by|payment is due|now due|rates invoice|power bill)\b/i },
    { category: 'reservation', dateType: 'reservation', score: 4, reason: 'booking or reservation language', re: /\b(booking confirmed|reservation confirmed|confirmed booking|confirmed reservation|check-in|check in|check-out|check out|itinerary|accommodation|hotel|airbnb|guest arrives|reservation)\b/i },
    { category: 'flight', dateType: 'flight_departure', score: 4, reason: 'flight or travel itinerary language', re: /\b(flight|boarding|departure|arrival|gate|itinerary|airline|qantas|air new zealand|jetstar)\b/i },
    { category: 'appointment', dateType: 'appointment', score: 4, reason: 'appointment language', re: /\b(appointment|scheduled for|reminder|dentist|dental|doctor|clinic|medical|meeting|site visit|inspection|booking is on)\b/i },
    { category: 'renewal', dateType: 'renewal', score: 4, reason: 'renewal or expiry language', re: /\b(renewal|renews|expires|expiry|registration|rego|wof|warrant of fitness|insurance renewal|subscription renewing|quote expires)\b/i },
    { category: 'council', dateType: 'bill_due', score: 4, reason: 'council, rates, or compliance language', re: /\b(council|qldc|queenstown lakes|rates|ird|tax|gst|compliance|notice|infringement)\b/i },
    { category: 'delivery', dateType: 'delivery', score: 3, reason: 'delivery or tracking language', re: /\b(delivery|tracking|arriving|expected tomorrow|out for delivery|courier|parcel)\b/i },
    { category: 'work_deadline', dateType: 'deadline', score: 4, reason: 'deadline or action-required language', re: /\b(deadline|due by|required by|submit by|complete by|finish by|before friday|before monday|action required|approval required|quote expires)\b/i },
    { category: 'legal_admin', dateType: 'deadline', score: 4, reason: 'legal or admin language', re: /\b(legal|lawyer|solicitor|contract|lease|agreement|admin|administration|compliance|notice)\b/i }
  ];

  const LOW_PRIORITY_RULES = [
    { reason: 'newsletter or digest', re: /\b(newsletter|digest|weekly update|monthly update|roundup|stories|read more)\b/i },
    { reason: 'promotion or sale', re: /\b(promo|promotion|sale|discount|deal|offer|clearance|reward|loyalty|points|shop now|black friday)\b/i },
    { reason: 'social media update', re: /\b(facebook|instagram|linkedin|tiktok|new followers?|likes?|mentioned you)\b/i },
    { reason: 'generic marketing sender', re: /\b(marketing|mailchimp|campaign|no-?reply|noreply|do not reply)\b/i }
  ];

  const CATEGORY_PRIORITY = {
    council: 8,
    flight: 8,
    bill: 7,
    reservation: 7,
    appointment: 7,
    renewal: 7,
    work_deadline: 7,
    legal_admin: 6,
    delivery: 5,
    general: 0
  };

  function cleanText(value) {
    return decodeHtmlEntities(String(value || ''))
      .replace(/\r?\n/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function stripHtml(value) {
    return decodeHtmlEntities(String(value || '')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<(br|\/p|\/div|\/li|\/tr|\/h[1-6])\b[^>]*>/gi, '\n')
      .replace(/<[^>]+>/g, ' '));
  }

  function decodeHtmlEntities(value) {
    return String(value || '')
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&apos;|&#39;/gi, "'")
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

  function simpleText(value) {
    return String(value || '')
      .toLowerCase()
      .replace(/[^a-z0-9@$./:-]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function parseAddress(raw) {
    const value = String(raw || '').trim();
    const emailMatch = value.match(/<([^>]+)>/) || value.match(/([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})/i);
    const email = emailMatch ? String(emailMatch[1] || emailMatch[0]).trim().toLowerCase() : '';
    let name = value.replace(/<[^>]+>/g, '').replace(/["']/g, '').trim();
    if (!name && email) name = email.split('@')[0].replace(/[._-]+/g, ' ');
    return { name, email };
  }

  function attachmentNameList(raw) {
    const out = [];
    (Array.isArray(raw && raw.attachments) ? raw.attachments : []).forEach(item => {
      const name = typeof item === 'string' ? item : item && item.name;
      if (name) out.push(String(name));
    });
    (Array.isArray(raw && raw.attachmentNames) ? raw.attachmentNames : []).forEach(name => {
      if (name && out.indexOf(String(name)) === -1) out.push(String(name));
    });
    return out;
  }

  function normalizeEmailMessage(raw) {
    raw = raw || {};
    const sender = parseAddress(raw.from || raw.sender || '');
    const htmlBody = String(raw.htmlBody || '');
    const plainTextBody = cleanText(raw.plainTextBody || '');
    const cleanedBodyText = cleanText(raw.cleanedBodyText || raw.body || plainTextBody || stripHtml(htmlBody));
    const attachments = (Array.isArray(raw.attachments) ? raw.attachments : []).map(item => {
      if (typeof item === 'string') return { name: item, mimeType: '', size: 0, scanned: false, kind: 'metadata', chars: 0, error: '' };
      return {
        name: String((item && item.name) || ''),
        mimeType: String((item && item.mimeType) || ''),
        size: Number((item && item.size) || 0),
        scanned: !!(item && item.scanned),
        kind: String((item && item.kind) || 'metadata'),
        chars: Number((item && item.chars) || 0),
        error: String((item && item.error) || '')
      };
    });
    const receivedAt = raw.receivedAt || raw.date || '';
    const threadId = String(raw.threadId || raw.conversationId || raw.id || '');
    const id = String(raw.id || threadId || '');
    return {
      id,
      threadId,
      provider: 'gmail',
      subject: String(raw.subject || ''),
      fromName: String(raw.fromName || sender.name || ''),
      fromEmail: String(raw.fromEmail || sender.email || ''),
      from: String(raw.from || ''),
      to: String(raw.to || ''),
      receivedAt,
      date: raw.date || receivedAt,
      snippet: cleanText(raw.snippet || '').slice(0, 1000),
      plainTextBody,
      cleanedBodyText,
      htmlBody,
      labels: Array.isArray(raw.labels) ? raw.labels.map(String) : [],
      attachments,
      attachmentNames: attachmentNameList(raw),
      attachmentText: cleanText(raw.attachmentText || ''),
      threadText: cleanText(raw.threadText || ''),
      source: raw.source || '',
      sourceUrl: raw.sourceUrl || (threadId ? 'https://mail.google.com/mail/u/0/#inbox/' + encodeURIComponent(threadId) : ''),
      rawMetadata: raw.rawMetadata || {
        id,
        threadId,
        labels: Array.isArray(raw.labels) ? raw.labels.map(String) : []
      },
      threadMessageIds: Array.isArray(raw.threadMessageIds) ? raw.threadMessageIds.map(String) : [id].filter(Boolean),
      threadMessageCount: Number(raw.threadMessageCount || 1)
    };
  }

  function dedupeMessagesByThread(messages) {
    const groups = new Map();
    (messages || []).map(normalizeEmailMessage).forEach(message => {
      const key = message.threadId || message.id;
      if (!key) return;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(message);
    });
    return Array.from(groups.values()).map(group => {
      group.sort((a, b) => new Date(b.receivedAt || 0) - new Date(a.receivedAt || 0));
      const primary = { ...group[0] };
      primary.threadMessageIds = group.map(item => item.id).filter(Boolean);
      primary.threadMessageCount = group.length;
      if (!primary.threadText && group.length > 1) {
        primary.threadText = cleanText(group.map(item => [item.subject, item.snippet, item.cleanedBodyText].join(' ')).join(' ')).slice(0, 12000);
      }
      return primary;
    }).sort((a, b) => new Date(b.receivedAt || 0) - new Date(a.receivedAt || 0));
  }

  function emailSearchText(message) {
    const attachmentNames = attachmentNameList(message).join(' ');
    return cleanText([
      message.subject,
      message.from,
      message.fromName,
      message.fromEmail,
      message.to,
      message.snippet,
      message.plainTextBody,
      message.cleanedBodyText,
      message.threadText,
      message.attachmentText,
      attachmentNames
    ].filter(Boolean).join(' '));
  }

  function dateScanText(message) {
    return cleanText([
      message.subject,
      message.snippet,
      message.plainTextBody,
      message.cleanedBodyText,
      message.threadText,
      message.attachmentText,
      attachmentNameList(message).join(' ')
    ].filter(Boolean).join(' '));
  }

  function parseToday(options) {
    const today = options && options.today ? parseIsoDate(options.today) : null;
    const d = today || new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }

  function referenceDate(message, options) {
    const received = new Date(message.receivedAt || message.date || '');
    if (!isNaN(received.getTime())) {
      received.setHours(0, 0, 0, 0);
      return received;
    }
    return parseToday(options);
  }

  function parseIsoDate(value) {
    const m = String(value || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!m) return null;
    const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    d.setHours(0, 0, 0, 0);
    return d.getFullYear() === Number(m[1]) && d.getMonth() === Number(m[2]) - 1 && d.getDate() === Number(m[3]) ? d : null;
  }

  function toIsoDate(date) {
    if (!date || isNaN(date.getTime())) return '';
    return [
      date.getFullYear(),
      String(date.getMonth() + 1).padStart(2, '0'),
      String(date.getDate()).padStart(2, '0')
    ].join('-');
  }

  function isoDateFromParts(day, month, year) {
    if (!Number.isInteger(day) || !Number.isInteger(month) || !Number.isInteger(year)) return '';
    if (year < 2000 || year > 2200) return '';
    const d = new Date(year, month - 1, day);
    d.setHours(0, 0, 0, 0);
    if (d.getFullYear() !== year || d.getMonth() !== month - 1 || d.getDate() !== day) return '';
    return toIsoDate(d);
  }

  function inferYear(month, day, refDate) {
    let year = refDate.getFullYear();
    const d = new Date(year, month - 1, day);
    d.setHours(0, 0, 0, 0);
    const tooFarPast = new Date(refDate);
    tooFarPast.setDate(tooFarPast.getDate() - 7);
    if (d < tooFarPast) year += 1;
    return year;
  }

  function parseLooseDate(raw, refDate) {
    const value = String(raw || '').trim();
    let m = value.match(/\b(20\d{2})-(\d{1,2})-(\d{1,2})\b/);
    if (m) return { isoDate: isoDateFromParts(Number(m[3]), Number(m[2]), Number(m[1])), inferred: false, assumption: '' };

    m = value.match(/\b(\d{1,2})[\/.-](\d{1,2})(?:[\/.-](\d{2,4}))?\b/);
    if (m) {
      const day = Number(m[1]);
      const month = Number(m[2]);
      let year = m[3] ? Number(m[3]) : inferYear(month, day, refDate);
      if (m[3] && String(m[3]).length === 2) year += 2000;
      return {
        isoDate: isoDateFromParts(day, month, year),
        inferred: !m[3],
        assumption: day <= 12 && month <= 12 ? 'Assumed NZ DD/MM date format.' : ''
      };
    }

    const monthNames = '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
    m = value.match(new RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+' + monthNames + '(?:\\s+(\\d{2,4}))?\\b', 'i'));
    if (m) {
      const day = Number(m[1]);
      const month = MONTH_INDEX[String(m[2] || '').toLowerCase()] + 1;
      let year = m[3] ? Number(m[3]) : inferYear(month, day, refDate);
      if (m[3] && String(m[3]).length === 2) year += 2000;
      return { isoDate: isoDateFromParts(day, month, year), inferred: !m[3], assumption: '' };
    }

    m = value.match(new RegExp('\\b' + monthNames + '\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{2,4}))?\\b', 'i'));
    if (m) {
      const month = MONTH_INDEX[String(m[1] || '').toLowerCase()] + 1;
      const day = Number(m[2]);
      let year = m[3] ? Number(m[3]) : inferYear(month, day, refDate);
      if (m[3] && String(m[3]).length === 2) year += 2000;
      return { isoDate: isoDateFromParts(day, month, year), inferred: !m[3], assumption: '' };
    }

    return { isoDate: '', inferred: false, assumption: '' };
  }

  function sourceSentence(text, index, length) {
    const value = String(text || '');
    const start = Math.max(0, value.lastIndexOf('.', index), value.lastIndexOf('\n', index), value.lastIndexOf('!', index), value.lastIndexOf('?', index));
    const endCandidates = ['.', '\n', '!', '?'].map(ch => {
      const found = value.indexOf(ch, index + length);
      return found === -1 ? value.length : found + 1;
    });
    const end = Math.min.apply(null, endCandidates);
    return cleanText(value.slice(start === 0 ? 0 : start + 1, end)).slice(0, 360);
  }

  function contextFor(text, index, length) {
    const value = String(text || '');
    return cleanText(value.slice(Math.max(0, index - 110), Math.min(value.length, index + length + 130)));
  }

  function timeFromContext(context) {
    let m = String(context || '').match(/\b(?:at\s*)?([01]?\d|2[0-3])[:.]([0-5]\d)\s*(am|pm)?\b/i);
    if (m) {
      let hour = Number(m[1]);
      const minute = Number(m[2]);
      const meridian = String(m[3] || '').toLowerCase();
      if (meridian === 'pm' && hour < 12) hour += 12;
      if (meridian === 'am' && hour === 12) hour = 0;
      return String(hour).padStart(2, '0') + ':' + String(minute).padStart(2, '0');
    }
    m = String(context || '').match(/\b(?:at\s*)?(1[0-2]|0?[1-9])\s*(am|pm)\b/i);
    if (m) {
      let hour = Number(m[1]);
      const meridian = String(m[2]).toLowerCase();
      if (meridian === 'pm' && hour < 12) hour += 12;
      if (meridian === 'am' && hour === 12) hour = 0;
      return String(hour).padStart(2, '0') + ':00';
    }
    return '';
  }

  function dateTypeFromContext(context, fallbackType) {
    const text = simpleText(context);
    if (/\b(check out|checkout|departure date|departs|leaving)\b/.test(text)) return 'check_out';
    if (/\b(check in|check-in|checkin|arrival date|guest arrives|arriving|starts)\b/.test(text)) return 'check_in';
    if (/\b(flight|departure|boarding)\b/.test(text)) return 'flight_departure';
    if (/\b(arrival|arrives)\b/.test(text) && /\b(flight|airline|airport)\b/.test(text)) return 'flight_arrival';
    if (/\b(registration|rego|wof|warrant of fitness)\b/.test(text)) return 'registration_expiry';
    if (/\b(appointment|scheduled for|dentist|doctor|clinic|meeting|inspection|site visit)\b/.test(text)) return 'appointment';
    if (/\b(renewal|renews|renewal date)\b/.test(text)) return 'renewal';
    if (/\b(expires|expiry|quote expires|valid until)\b/.test(text)) return 'quote_expiry';
    if (/\b(delivery|tracking|courier|arriving|expected)\b/.test(text)) return 'delivery';
    if (/\b(due|payment due|amount due|pay by|pay before|overdue|balance due|total due|due date|invoice due)\b/.test(text)) return 'bill_due';
    if (/\b(deadline|required by|submit by|complete by|before)\b/.test(text)) return 'deadline';
    if (/\b(booking|reservation|confirmed for|booked for|itinerary)\b/.test(text)) return 'reservation';
    return fallbackType || 'event';
  }

  function isMeaningfulDateType(type) {
    return [
      'bill_due', 'payment_deadline', 'reservation', 'check_in', 'check_out',
      'flight_departure', 'flight_arrival', 'appointment', 'renewal',
      'quote_expiry', 'delivery', 'registration_expiry', 'event', 'deadline'
    ].indexOf(type) !== -1;
  }

  function addDateResult(results, seen, message, fullText, index, rawText, isoDate, opts) {
    opts = opts || {};
    if (!isoDate) return;
    const d = parseIsoDate(isoDate);
    if (!d) return;
    const ref = referenceDate(message, opts);
    const earliest = new Date(ref);
    earliest.setDate(earliest.getDate() - 31);
    const latest = new Date(ref);
    latest.setMonth(latest.getMonth() + 18);
    if (d < earliest || d > latest) return;

    const context = opts.context || contextFor(fullText, index, rawText.length);
    const source = opts.sourceSentence || sourceSentence(fullText, index, rawText.length) || context;
    const dateType = opts.dateType || dateTypeFromContext(context, opts.fallbackType);
    const parsedTime = opts.time !== undefined ? opts.time : timeFromContext(context);
    let confidence = opts.confidence || 0.72;
    if (/\b(due date|payment due|pay by|check-in|check in|check-out|appointment|scheduled for|renewal date|expires|delivery expected|departure|arrival)\b/i.test(context)) confidence += 0.16;
    if (opts.inferred) confidence -= 0.08;
    if (opts.relative) confidence -= 0.04;
    confidence = Math.max(0.35, Math.min(0.98, confidence));

    const key = [isoDate, parsedTime, dateType, rawText.toLowerCase()].join('|');
    if (seen.has(key)) return;
    seen.add(key);
    results.push({
      rawText,
      isoDate,
      parsedTime,
      dateType,
      confidence: Math.round(confidence * 100) / 100,
      sourceSentence: source,
      confirmed: !opts.inferred && !opts.relative,
      needsReview: !!opts.needsReview || confidence < 0.72,
      assumption: opts.assumption || '',
      inferred: !!opts.inferred || !!opts.relative
    });
  }

  function nextWeekdayDate(refDate, weekday, forceNext) {
    const d = new Date(refDate);
    d.setHours(0, 0, 0, 0);
    let delta = (weekday - d.getDay() + 7) % 7;
    if (forceNext || delta === 0) delta = delta || 7;
    d.setDate(d.getDate() + delta);
    return d;
  }

  function extractDates(message, options) {
    message = normalizeEmailMessage(message);
    const text = dateScanText(message);
    const ref = referenceDate(message, options);
    const results = [];
    const seen = new Set();
    const monthNames = '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
    const patterns = [
      /\b(20\d{2}-\d{1,2}-\d{1,2})\b/g,
      /\b(\d{1,2}[\/.-]\d{1,2}(?:[\/.-]\d{2,4})?)\b/g,
      new RegExp('\\b(\\d{1,2}(?:st|nd|rd|th)?\\s+' + monthNames + '(?:\\s+\\d{2,4})?)\\b', 'gi'),
      new RegExp('\\b(' + monthNames + '\\s+\\d{1,2}(?:st|nd|rd|th)?(?:,?\\s+\\d{2,4})?)\\b', 'gi')
    ];

    patterns.forEach(pattern => {
      for (const match of text.matchAll(pattern)) {
        const rawText = match[1] || match[0];
        const parsed = parseLooseDate(rawText, ref);
        addDateResult(results, seen, message, text, match.index || 0, rawText, parsed.isoDate, {
          inferred: parsed.inferred,
          assumption: parsed.assumption,
          confidence: parsed.assumption ? 0.8 : 0.76,
          today: options && options.today
        });
      }
    });

    for (const match of text.matchAll(/\b(today|tomorrow)\b/gi)) {
      const raw = match[1];
      const d = new Date(ref);
      if (/tomorrow/i.test(raw)) d.setDate(d.getDate() + 1);
      const context = contextFor(text, match.index || 0, raw.length);
      if (!contextLooksDateUseful(context)) continue;
      addDateResult(results, seen, message, text, match.index || 0, raw, toIsoDate(d), {
        relative: true,
        context,
        confidence: 0.78,
        today: options && options.today
      });
    }

    for (const match of text.matchAll(/\b(?:(due|pay|pay by|due by|before|scheduled for|appointment(?: is)?|booking(?: is)?|reservation(?: is| confirmed)?|delivery expected|expires?|quote expires)\s+(?:on|by|for)?\s*|(?:on|by|before)\s+)?(next\s+)?(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b/gi)) {
      const dayName = String(match[3] || '').toLowerCase();
      const weekday = WEEKDAY_INDEX[dayName];
      if (weekday === undefined) continue;
      const context = contextFor(text, match.index || 0, match[0].length);
      if (!contextLooksDateUseful(context)) continue;
      const d = nextWeekdayDate(ref, weekday, !!match[2]);
      addDateResult(results, seen, message, text, match.index || 0, match[0], toIsoDate(d), {
        relative: true,
        context,
        confidence: 0.76,
        today: options && options.today
      });
    }

    for (const match of text.matchAll(/\b(?:due|payment is due|pay|expires?|quote expires|delivery expected|arriving|renew(?:s|al)?|required)\s+(?:in\s+)?(\d{1,3})\s+days?\b/gi)) {
      const days = Number(match[1]);
      if (!Number.isFinite(days) || days < 0 || days > 370) continue;
      const d = new Date(ref);
      d.setDate(d.getDate() + days);
      const context = contextFor(text, match.index || 0, match[0].length);
      addDateResult(results, seen, message, text, match.index || 0, match[0], toIsoDate(d), {
        relative: true,
        context,
        confidence: 0.8,
        today: options && options.today
      });
    }

    return results.sort((a, b) =>
      a.isoDate.localeCompare(b.isoDate) ||
      (b.confidence - a.confidence) ||
      a.dateType.localeCompare(b.dateType)
    );
  }

  function contextLooksDateUseful(context) {
    return /\b(due|deadline|required by|before|pay by|payable|payment|invoice|bill|rates|appointment|scheduled|booking|booked|reservation|check-in|check in|check-out|flight|departure|arrival|renewal|expires|expiry|delivery|tracking|registration|rego|wof|event|meeting|quote)\b/i.test(context);
  }

  function extractAmounts(text) {
    const value = String(text || '');
    const results = [];
    const seen = new Set();
    const patterns = [
      /\b(?:amount owing|amount due|balance due|total due|owing|payable|payment|invoice|bill)\b[\s\S]{0,180}?(\$\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\bNZD\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?)/gi,
      /(\$\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\bNZD\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?)[\s\S]{0,180}?\b(?:due|owing|pay now|amount due|payment due|invoice|bill)\b/gi
    ];
    patterns.forEach(pattern => {
      for (const match of value.matchAll(pattern)) {
        const raw = match[1] || match[0];
        const amount = normalizeAmount(raw);
        if (!amount || seen.has(amount)) continue;
        seen.add(amount);
        results.push({
          rawText: raw,
          amount,
          confidence: 0.84,
          sourceSentence: sourceSentence(value, match.index || 0, match[0].length)
        });
      }
    });
    return results;
  }

  function normalizeAmount(raw) {
    let value = String(raw || '').trim().replace(/\s+/g, '');
    if (!value) return '';
    if (/^nzd/i.test(value)) value = '$' + value.replace(/^nzd/i, '');
    return value;
  }

  function classifyEmail(message, dates, amounts, options) {
    const text = emailSearchText(message);
    const haystack = [message.from, message.subject, text].join(' ');
    const rulesMatched = [];
    let category = 'general';
    let dateType = 'event';
    let score = 2;
    let categoryPriority = CATEGORY_PRIORITY.general;

    CATEGORY_RULES.forEach(rule => {
      if (!rule.re.test(haystack)) return;
      rulesMatched.push(rule.reason);
      const priority = CATEGORY_PRIORITY[rule.category] || 0;
      if (rule.score > score || (rule.score === score && priority > categoryPriority)) {
        score = rule.score;
        category = rule.category;
        dateType = rule.dateType;
        categoryPriority = priority;
      }
    });

    const lowMatches = LOW_PRIORITY_RULES.filter(rule => rule.re.test(haystack)).map(rule => rule.reason);
    const hasImportantDate = (dates || []).some(date => isMeaningfulDateType(date.dateType) && date.confidence >= 0.68);
    if (lowMatches.length && score < 4 && !hasImportantDate && !amounts.length) {
      score = 1;
      category = 'low_priority';
      rulesMatched.push.apply(rulesMatched, lowMatches);
    }

    if (amounts.length && score < 4) {
      score = 3;
      category = category === 'general' ? 'bill' : category;
      rulesMatched.push('amount detected');
    }

    const today = parseToday(options);
    const urgentDate = (dates || []).find(date => {
      const d = parseIsoDate(date.isoDate);
      return d && date.confidence >= 0.68 && d.getTime() - today.getTime() <= 3 * MS_DAY && d >= today;
    });
    if (urgentDate && score >= 4) {
      score = 5;
      rulesMatched.push('date is within 3 days');
    }

    score = Math.max(1, Math.min(5, score));
    const reason = score === 1
      ? 'Low priority: ' + (lowMatches[0] || 'no clear action or date found')
      : rulesMatched.slice(0, 4).join('; ') || 'No strong rule matched';

    return {
      category,
      likelyDateType: dateType,
      importanceScore: score,
      importanceReason: reason,
      rulesMatched: uniqueStrings(rulesMatched),
      lowPriority: score <= 2
    };
  }

  function uniqueStrings(values) {
    const seen = new Set();
    return (values || []).filter(value => {
      const key = String(value || '').toLowerCase();
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  function senderLabel(message) {
    return message.fromName || message.fromEmail || message.from || 'Gmail sender';
  }

  function buildSummary(message, classification, dates, amounts) {
    const amount = amounts[0] && amounts[0].amount;
    const bestDate = dates.find(date => isMeaningfulDateType(date.dateType)) || dates[0];
    const subject = cleanSubject(message.subject);
    const who = senderLabel(message);
    const action = actionForCategory(classification.category, bestDate);
    const bits = [];
    bits.push(subject ? subject + ' from ' + who + '.' : 'Email from ' + who + '.');
    if (amount) bits.push('Amount found: ' + amount + '.');
    if (bestDate) bits.push(dateTypeLabel(bestDate.dateType) + ' is ' + bestDate.isoDate + (bestDate.parsedTime ? ' at ' + bestDate.parsedTime : '') + '.');
    bits.push(action);
    bits.push('Marked ' + classification.importanceScore + '/5 because ' + classification.importanceReason + '.');
    return bits.filter(Boolean).join(' ');
  }

  function cleanSubject(subject) {
    return cleanText(subject || 'Gmail item').replace(/^\s*(re|fw|fwd)\s*:\s*/i, '').trim();
  }

  function actionForCategory(category, date) {
    if (category === 'bill' || (date && date.dateType === 'bill_due')) return 'Add to bills calendar or mark as paid.';
    if (category === 'reservation') return 'Check booking details and add the relevant dates.';
    if (category === 'appointment') return 'Add the appointment and check whether anything needs preparing.';
    if (category === 'renewal') return 'Review the renewal or expiry before the date.';
    if (category === 'delivery') return 'Track delivery and watch the expected date.';
    if (category === 'work_deadline') return 'Review the requested work and deadline.';
    return 'Review or dismiss it from the inbox briefing.';
  }

  function dateTypeLabel(type) {
    const labels = {
      bill_due: 'Due date',
      payment_deadline: 'Payment deadline',
      reservation: 'Reservation date',
      check_in: 'Check-in',
      check_out: 'Check-out',
      flight_departure: 'Flight departure',
      flight_arrival: 'Flight arrival',
      appointment: 'Appointment',
      renewal: 'Renewal date',
      quote_expiry: 'Quote expiry',
      delivery: 'Delivery date',
      registration_expiry: 'Registration expiry',
      deadline: 'Deadline',
      event: 'Event date'
    };
    return labels[type] || 'Date';
  }

  function kindForDateType(type) {
    if (type === 'appointment' || type === 'flight_departure' || type === 'flight_arrival' || type === 'event') return 'meeting';
    if (type === 'check_in' || type === 'check_out' || type === 'reservation') return 'stay';
    if (type === 'delivery' || type === 'renewal') return 'info';
    return 'task';
  }

  function titleForSuggestion(message, classification, date, amount) {
    const subject = cleanSubject(message.subject);
    const prefix = {
      bill: 'Bill',
      council: 'Council/rates',
      reservation: 'Booking',
      flight: 'Flight',
      appointment: 'Appointment',
      renewal: 'Renewal',
      delivery: 'Delivery',
      work_deadline: 'Deadline',
      legal_admin: 'Admin'
    }[classification.category] || dateTypeLabel(date.dateType);
    const amountText = amount ? ' ' + amount : '';
    return cleanText(prefix + ': ' + (subject || senderLabel(message)) + amountText).slice(0, 180);
  }

  function calendarSuggestionFromDate(message, classification, dates, amounts, summary, date, index) {
    const amount = amounts[0] && amounts[0].amount || '';
    const threadKey = message.threadId || message.id || senderLabel(message);
    return {
      id: [message.id || threadKey, date.dateType, index].join('-'),
      sourceKey: ['gmail', threadKey, date.dateType, date.isoDate, date.parsedTime || '', amount].join('|'),
      kind: kindForDateType(date.dateType),
      date: date.isoDate,
      endDate: '',
      time: date.parsedTime || '',
      title: titleForSuggestion(message, classification, date, amount),
      amount,
      category: classification.category,
      dateType: date.dateType,
      summary,
      context: date.sourceSentence || summary,
      rawDate: date.rawText,
      sourceEmailId: message.id,
      sourceThreadId: message.threadId,
      sourceSubject: message.subject,
      sourceFrom: senderLabel(message),
      sourceSender: senderLabel(message),
      sourceDate: message.receivedAt,
      sourceUrl: message.sourceUrl,
      provider: 'gmail',
      confidence: Math.round(Math.min(date.confidence, 0.55 + classification.importanceScore / 10) * 100) / 100,
      status: 'suggested',
      needsReview: !!date.needsReview || classification.importanceScore < 4,
      importanceScore: classification.importanceScore,
      importanceReason: classification.importanceReason,
      rulesMatched: classification.rulesMatched,
      extractedDates: dates,
      extractedAmounts: amounts,
      message,
      debug: {
        rawMetadata: message.rawMetadata,
        cleanedBodyText: message.cleanedBodyText,
        labels: message.labels,
        attachments: message.attachments,
        category: classification.category,
        importanceScore: classification.importanceScore,
        importanceReason: classification.importanceReason,
        rulesMatched: classification.rulesMatched,
        extractedDates: dates,
        extractedAmounts: amounts,
        parsingErrors: [],
        aiResponse: ''
      }
    };
  }

  function reviewSuggestionFromEmail(message, classification, dates, amounts, summary) {
    const amount = amounts[0] && amounts[0].amount || '';
    const threadKey = message.threadId || message.id || senderLabel(message);
    return {
      id: [message.id || threadKey, 'needs-review'].join('-'),
      sourceKey: ['gmail', threadKey, 'needs-review', classification.category, amount].join('|'),
      kind: classification.category === 'appointment' ? 'meeting' : 'task',
      date: '',
      endDate: '',
      time: '',
      title: titleForSuggestion(message, classification, { dateType: classification.likelyDateType || 'deadline' }, amount),
      amount,
      category: classification.category,
      dateType: classification.likelyDateType || 'deadline',
      summary,
      context: summary,
      rawDate: 'Needs date review',
      sourceEmailId: message.id,
      sourceThreadId: message.threadId,
      sourceSubject: message.subject,
      sourceFrom: senderLabel(message),
      sourceSender: senderLabel(message),
      sourceDate: message.receivedAt,
      sourceUrl: message.sourceUrl,
      provider: 'gmail',
      confidence: 0.55,
      status: 'suggested',
      needsReview: true,
      needsDate: true,
      importanceScore: classification.importanceScore,
      importanceReason: classification.importanceReason,
      rulesMatched: classification.rulesMatched,
      extractedDates: dates,
      extractedAmounts: amounts,
      message,
      debug: {
        rawMetadata: message.rawMetadata,
        cleanedBodyText: message.cleanedBodyText,
        labels: message.labels,
        attachments: message.attachments,
        category: classification.category,
        importanceScore: classification.importanceScore,
        importanceReason: classification.importanceReason,
        rulesMatched: classification.rulesMatched,
        extractedDates: dates,
        extractedAmounts: amounts,
        parsingErrors: ['No meaningful date found deterministically.'],
        aiResponse: ''
      }
    };
  }

  function analyzeEmail(raw, options) {
    const message = normalizeEmailMessage(raw);
    const text = emailSearchText(message);
    const dates = extractDates(message, options);
    const amounts = extractAmounts(text);
    const classification = classifyEmail(message, dates, amounts, options);
    const summary = buildSummary(message, classification, dates, amounts);
    return {
      message,
      text,
      dates,
      amounts,
      classification,
      summary
    };
  }

  function buildEmailBriefing(rawMessages, options) {
    options = options || {};
    const suggestions = [];
    const debugRecords = [];
    const seenEvents = new Set();
    const messages = dedupeMessagesByThread(rawMessages);
    messages.forEach((message, messageIndex) => {
      const analysis = analyzeEmail(message, options);
      debugRecords.push({
        id: message.id,
        threadId: message.threadId,
        subject: message.subject,
        from: senderLabel(message),
        receivedAt: message.receivedAt,
        sourceUrl: message.sourceUrl,
        category: analysis.classification.category,
        importanceScore: analysis.classification.importanceScore,
        importanceReason: analysis.classification.importanceReason,
        rulesMatched: analysis.classification.rulesMatched,
        extractedDates: analysis.dates,
        extractedAmounts: analysis.amounts,
        summary: analysis.summary,
        cleanedBodyText: message.cleanedBodyText,
        rawMetadata: message.rawMetadata,
        attachments: message.attachments,
        lowPriority: analysis.classification.lowPriority
      });

      if (analysis.classification.importanceScore <= 2) return;
      const meaningfulDates = analysis.dates.filter(date => isMeaningfulDateType(date.dateType) && date.confidence >= 0.62);
      if (!meaningfulDates.length) {
        if (analysis.classification.importanceScore >= 4) {
          const item = reviewSuggestionFromEmail(message, analysis.classification, analysis.dates, analysis.amounts, analysis.summary);
          suggestions.push(item);
        }
        return;
      }
      meaningfulDates.slice(0, 4).forEach((date, dateIndex) => {
        const item = calendarSuggestionFromDate(message, analysis.classification, analysis.dates, analysis.amounts, analysis.summary, date, dateIndex);
        const key = item.sourceKey;
        if (seenEvents.has(key)) return;
        seenEvents.add(key);
        suggestions.push(item);
      });
    });

    suggestions.sort((a, b) =>
      (b.importanceScore || 0) - (a.importanceScore || 0) ||
      (a.date || '9999-12-31').localeCompare(b.date || '9999-12-31') ||
      (a.time || '').localeCompare(b.time || '') ||
      String(a.title || '').localeCompare(String(b.title || ''))
    );

    return {
      timezone: options.timezone || DEFAULT_TIMEZONE,
      suggestions,
      debugRecords,
      hiddenLowPriorityCount: debugRecords.filter(record => record.lowPriority).length
    };
  }

  return {
    DEFAULT_TIMEZONE,
    normalizeEmailMessage,
    dedupeMessagesByThread,
    emailSearchText,
    extractDates,
    extractAmounts,
    classifyEmail,
    analyzeEmail,
    buildEmailBriefing,
    cleanText,
    stripHtml,
    parseLooseDate
  };
});
