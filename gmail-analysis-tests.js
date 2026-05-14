const assert = require('assert');
const gmail = require('./gmail-analysis-core');

const options = { today: '2026-05-14', timezone: 'Pacific/Auckland' };

function email(overrides) {
  return {
    id: overrides.id,
    threadId: overrides.threadId || overrides.id,
    receivedAt: overrides.receivedAt || '2026-05-14T09:00:00+12:00',
    subject: overrides.subject || '',
    from: overrides.from || 'Sender <sender@example.co.nz>',
    snippet: overrides.snippet || '',
    plainTextBody: overrides.plainTextBody || '',
    htmlBody: overrides.htmlBody || '',
    cleanedBodyText: overrides.cleanedBodyText || overrides.body || '',
    labels: overrides.labels || ['INBOX'],
    attachments: overrides.attachments || [],
    sourceUrl: `https://mail.google.com/mail/u/0/#inbox/${overrides.threadId || overrides.id}`,
    provider: 'gmail'
  };
}

const fixtures = [
  email({
    id: 'bill-1',
    subject: 'Your Meridian power bill',
    from: 'Meridian Energy <billing@meridian.co.nz>',
    body: 'Power bill from Meridian. Amount due $243.50. Payment is due by 15 June 2026.'
  }),
  email({
    id: 'hotel-1',
    subject: 'Booking confirmed',
    from: 'Hotel Reservations <stay@example.com>',
    body: 'Your booking is confirmed. Check-in 3 September 2026. Check-out 8 September 2026.'
  }),
  email({
    id: 'flight-1',
    subject: 'Flight itinerary',
    from: 'Air New Zealand <itinerary@airnz.co.nz>',
    body: 'Flight NZ623 departure 7:30pm on 21 May 2026. Arrival 9:00pm on 21 May 2026.'
  }),
  email({
    id: 'rates-1',
    subject: 'QLDC rates notice',
    from: 'Queenstown Lakes District Council <rates@qldc.govt.nz>',
    body: 'Your quarterly rates invoice is now due. Amount owing $1,204.10. Due date 20 May 2026.'
  }),
  email({
    id: 'rego-1',
    subject: 'Vehicle registration renewal',
    from: 'NZTA <noreply@nzta.govt.nz>',
    body: 'Your car registration expires on 1 July 2026. Renew before the expiry date.'
  }),
  email({
    id: 'dental-1',
    subject: 'Dental appointment reminder',
    from: 'Dental Clinic <reception@dental.example>',
    body: 'Reminder: your dental appointment is scheduled for 7:30pm on 21 May.'
  }),
  email({
    id: 'delivery-1',
    subject: 'Delivery update',
    from: 'Courier <tracking@courier.example>',
    body: 'Your delivery is expected tomorrow. Tracking number ABC123.'
  }),
  email({
    id: 'newsletter-1',
    subject: 'May newsletter',
    from: 'Brand Newsletter <news@brand.example>',
    body: 'Our weekly newsletter. Read more stories and shop our latest range.'
  }),
  email({
    id: 'promo-1',
    subject: 'Huge sale today',
    from: 'Store Deals <promo@store.example>',
    body: 'Promotion only. Save 30 percent. Shop now.'
  }),
  email({
    id: 'work-1',
    subject: 'Plan review deadline',
    from: 'Alex Client <alex@example.co.nz>',
    body: 'Can you please send the plan review due by Friday? The approval is required before Monday.'
  }),
  email({
    id: 'sub-1',
    subject: 'Subscription renewal',
    from: 'Software Billing <billing@software.example>',
    body: 'Your subscription renews in 14 days. The renewal amount is $59.00.'
  })
];

function hasSuggestion(briefing, predicate, label) {
  assert.ok(briefing.suggestions.some(predicate), label);
}

// Gmail body normalisation: HTML-only messages become cleaned readable text.
{
  const normalized = gmail.normalizeEmailMessage(email({
    id: 'html-1',
    subject: 'HTML invoice',
    htmlBody: '<html><body><h1>Invoice</h1><p>Payment is due on 15 June 2026.</p></body></html>'
  }));
  assert.ok(normalized.cleanedBodyText.includes('Payment is due on 15 June 2026'), 'HTML body should be stripped into cleaned text');
}

// Duplicate thread detection keeps one analysis target per Gmail thread.
{
  const deduped = gmail.dedupeMessagesByThread([
    email({ id: 'dup-a', threadId: 'thread-1', body: 'Invoice due 20 May 2026.' }),
    email({ id: 'dup-b', threadId: 'thread-1', receivedAt: '2026-05-15T09:00:00+12:00', body: 'Follow-up invoice due 20 May 2026.' })
  ]);
  assert.strictEqual(deduped.length, 1, 'same Gmail thread should be deduped');
  assert.strictEqual(deduped[0].id, 'dup-b', 'latest thread message should be retained');
}

// Date extraction examples.
{
  const samples = [
    ['due on 15 June', '2026-06-15'],
    ['due by Friday', '2026-05-15'],
    ['payment is due in 7 days', '2026-05-21'],
    ['check-in 3 September', '2026-09-03'],
    ['check-out 8 September', '2026-09-08'],
    ['reservation confirmed for 7:30pm on 21 May', '2026-05-21'],
    ['your booking is on 12/06/2026', '2026-06-12'],
    ['renewal date: 1 July 2026', '2026-07-01'],
    ['invoice due date 20 May 2026', '2026-05-20'],
    ['delivery expected tomorrow', '2026-05-15'],
    ['quote expires in 14 days', '2026-05-28']
  ];
  samples.forEach(([text, iso]) => {
    const dates = gmail.extractDates(email({ id: `date-${iso}`, body: text }), options);
    assert.ok(dates.some(date => date.isoDate === iso), `expected ${text} to parse as ${iso}`);
  });
}

// Amount extraction and category classification.
{
  const analysis = gmail.analyzeEmail(fixtures[0], options);
  assert.strictEqual(analysis.amounts[0].amount, '$243.50', 'bill amount should be extracted');
  assert.strictEqual(analysis.classification.category, 'bill', 'bill should be classified as bill');
  assert.ok(analysis.classification.importanceScore >= 4, 'bill should be important');

  const newsletter = gmail.analyzeEmail(fixtures[7], options);
  assert.strictEqual(newsletter.classification.importanceScore, 1, 'newsletter should be low priority');
}

// Calendar event creation across common inbox patterns.
{
  const briefing = gmail.buildEmailBriefing(fixtures, options);
  hasSuggestion(briefing, item => item.category === 'bill' && item.date === '2026-06-15', 'bill due date suggestion missing');
  hasSuggestion(briefing, item => item.category === 'reservation' && item.date === '2026-09-03', 'booking check-in suggestion missing');
  hasSuggestion(briefing, item => item.category === 'flight' && item.time === '19:30', 'flight departure time missing');
  hasSuggestion(briefing, item => item.category === 'council' && item.amount === '$1,204.10', 'council rates amount missing');
  hasSuggestion(briefing, item => item.category === 'renewal' && item.dateType === 'registration_expiry', 'car registration expiry missing');
  hasSuggestion(briefing, item => item.category === 'appointment' && item.time === '19:30', 'dental appointment time missing');
  hasSuggestion(briefing, item => item.category === 'delivery' && item.date === '2026-05-15', 'delivery date missing');
  hasSuggestion(briefing, item => item.category === 'work_deadline' && item.date === '2026-05-15', 'work deadline missing');
  hasSuggestion(briefing, item => item.category === 'renewal' && item.date === '2026-05-28', 'subscription renewal missing');
  assert.ok(!briefing.suggestions.some(item => item.sourceEmailId === 'newsletter-1'), 'newsletter should not create a calendar item');
  assert.ok(!briefing.suggestions.some(item => item.sourceEmailId === 'promo-1'), 'promotion should not create a calendar item');
}

console.log('Gmail analysis tests passed.');
