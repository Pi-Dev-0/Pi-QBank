/**
 * Tests for the Apps Script request handling.
 *
 * Run with:  node --test google_apps_script/HighSchool_QBank_Script.test.js
 *
 * The regression these lock down: an earlier version of doPost rewrote every
 * "+" in the body to a space before parsing, because the uploader posts
 * text/plain where "+" is a literal plus. Every maths question containing
 * arithmetic was silently corrupted — "4(AM² + CN²)" reached the sheet as
 * "4(AM²   CN²)" — and the upload still reported success.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

/**
 * Load the Apps Script source with the Google globals stubbed out.
 *
 * Only the pure helpers are exercised, so the stubs just have to exist; they
 * are never reached.
 */
function loadScript() {
  const source = fs.readFileSync(
    path.join(__dirname, 'HighSchool_QBank_Script.js'),
    'utf8'
  );

  const noop = () => {
    throw new Error('Google API called in a unit test');
  };
  const stub = new Proxy({}, { get: () => noop });

  const context = vm.createContext({
    SpreadsheetApp: stub,
    PropertiesService: stub,
    CacheService: stub,
    LockService: stub,
    HtmlService: stub,
    Utilities: { sleep: () => {}, base64Encode: (s) => s },
    console,
    JSON,
    Math,
    Date,
    String,
    Number,
    Array,
    Object,
    Error,
    RegExp,
    isNaN,
    parseInt,
    parseFloat,
  });

  vm.runInContext(source, context);
  return context;
}

const script = loadScript();

test('a literal plus in text/plain survives the round trip', () => {
  const stem = 'প্রমাণ করো যে, 5AC² = 4(AM² + CN²)';
  const body = JSON.stringify({
    action: 'addQuestions',
    questions: [
      {
        class: 'Class (9-10) SSC',
        question_type: 'CQ',
        stem_text: stem,
      },
    ],
  });

  const parsed = script.parseRequestBody({
    postData: { contents: body, type: 'text/plain;charset=utf-8' },
  });

  assert.strictEqual(parsed.questions[0].stem_text, stem);
});

test('the plus is not confused with an encoded space', () => {
  // "a + b" and "a   b" are different strings and must stay different.
  const parsed = script.parseRequestBody({
    postData: {
      contents: JSON.stringify({ questions: [{ stem_text: 'a + b' }] }),
      type: 'text/plain;charset=utf-8',
    },
  });
  assert.strictEqual(parsed.questions[0].stem_text, 'a + b');
});

test('a urlencoded body still decodes "+" as a space', () => {
  // Some client posts form-encoded JSON, where "+" does mean a space.
  const parsed = script.parseRequestBody({
    postData: {
      contents: JSON.stringify({ questions: [{ stem_text: 'a + b' }] }),
      type: 'application/x-www-form-urlencoded',
    },
  });
  assert.strictEqual(parsed.questions[0].stem_text, 'a + b');
});

test('an empty or missing body is reported clearly', () => {
  assert.throws(
    () => script.parseRequestBody({ postData: { contents: '' } }),
    /Empty request body/
  );
  assert.throws(() => script.parseRequestBody({}), /Empty request body/);
});

test('a non-JSON body is reported clearly instead of a raw parse error', () => {
  assert.throws(
    () =>
      script.parseRequestBody({
        postData: { contents: 'not json at all', type: 'text/html' },
      }),
    /could not parse it as JSON/
  );
});

test('the bulk row write passes no input option', () => {
  // Both ways of asking for RAW break this deployment's uploads:
  //   SpreadsheetApp.InputOption.RAW -> "Cannot read properties of undefined"
  //   "RAW"                          -> "parameters do not match the method signature"
  // A "+" in the middle of a sentence is plain text under USER_ENTERED, which
  // is all the question bank needs, so the write must stay single-argument.
  const source = fs.readFileSync(
    path.join(__dirname, 'HighSchool_QBank_Script.js'),
    'utf8'
  );
  const writes = source.match(/\.setValues\(([^;]*?)\)/g) || [];
  const bulkWrites = writes.filter((w) => /rows\b/.test(w));
  assert.ok(bulkWrites.length > 0, 'expected at least one bulk row write');
  for (const w of bulkWrites) {
    const args = w.slice('setValues('.length, -1);
    assert.ok(
      !args.includes(','),
      `the bulk write passes a second argument and will fail on this runtime: ${w}`
    );
  }
});

test('no unresolvable enum or string input option is used anywhere', () => {
  const source = fs.readFileSync(
    path.join(__dirname, 'HighSchool_QBank_Script.js'),
    'utf8'
  );
  // Comments are allowed to name the rejected forms — the warning does. Only
  // executable code is checked.
  const code = source
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  assert.ok(
    !/setValues\([^)]*,/.test(code),
    'a setValues call passes a second argument; see the note at the bulk write'
  );
  assert.ok(
    !/SpreadsheetApp\.InputOption/.test(code),
    'SpreadsheetApp.InputOption is undefined on this runtime'
  );
});