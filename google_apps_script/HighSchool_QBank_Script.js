/**
 * Pi-QBank — HighSchool Question Bank
 * Google Apps Script Backend
 *
 * Sheet Name: HighSchool_Questions
 * Columns (1-indexed):
 *  A  = id
 *  B  = class
 *  C  = subject
 *  D  = chapter_number
 *  E  = chapter_name
 *  F  = question_type  (CQ | MCQ | RQ)
 *
 * sub_questions_json shape depends on the type:
 *   CQ  -> [ { label, mark, text }, ... ]
 *   MCQ -> { text, options: [...], correct_ans }
 *   RQ  -> { text, mark }                (short answer question)
 *  G  = stem_text
 *  H  = stem_image_url
 *  I  = sub_questions_json
 *  J  = board_year_tag
 *
 * Deploy → Web App → Execute as: Me | Who has access: Anyone
 */

const SHEET_NAME = "HighSchool_Questions";
const HEADERS = [
  "id",
  "class",
  "subject",
  "chapter_number",
  "chapter_name",
  "question_type",
  "stem_text",
  "stem_image_url",
  "sub_questions_json",
  "board_year_tag",
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function getSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
    sheet.appendRow(HEADERS);
    sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight("bold");
    sheet.setFrozenRows(1);
  }
  return sheet;
}

function generateId() {
  return Utilities.getUuid();
}

/**
 * All ids currently in column A, lower-cased for case-insensitive comparison.
 *
 * Read as a lookup keyed by the id rather than a flat list so a large sheet
 * stays O(n) per check instead of O(n) per question.
 */
function readExistingIds(sheet) {
  const ids = Object.create(null);
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return ids;

  const columnA = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  for (let i = 0; i < columnA.length; i++) {
    const v = String(columnA[i][0] == null ? "" : columnA[i][0]).trim();
    if (v) ids[v.toLowerCase()] = true;
  }
  return ids;
}

function jsonResponse(data) {
  const payload = JSON.stringify(data);
  return ContentService.createTextOutput(payload)
    .setMimeType(ContentService.MimeType.JSON);
}

// ─────────────────────────────────────────────────────────────────────────────
// Canonical class list (must stay in sync with the app + web uploader)
//
//   Class 6 | Class 7 | Class 8 | Class (9-10) SSC | Class (11-12) HSC
//
// Rows written before this split carry grouped labels ("Class 6-8", "Class 9-10",
// "Class 11-12 (HSC)"). LEGACY_CLASS_ALIASES maps each canonical class to the
// old labels that should still resolve to it, so pre-split data keeps showing up
// instead of silently disappearing. Re-tag those rows in the sheet with a
// specific class and the alias can be dropped.
//
// New uploads are normalised to a canonical label (see canonicalizeClass), so
// ambiguous old labels are rejected on write rather than stored.
// ─────────────────────────────────────────────────────────────────────────────

const CANONICAL_CLASSES = [
  "Class 6",
  "Class 7",
  "Class 8",
  "Class (9-10) SSC",
  "Class (11-12) HSC",
];

const LEGACY_CLASS_ALIASES = {
  "class 6":           ["class 6-8"],
  "class 7":           ["class 6-8"],
  "class 8":           ["class 6-8"],
  "class (9-10) ssc":  ["class 9-10", "class 9-10 ssc"],
  "class (11-12) hsc": ["class 11-12 (hsc)", "class 11-12 hsc"],
};

function _norm(value) {
  return String(value == null ? "" : value).trim().toLowerCase();
}

function _canonicalLabel(lowerKey) {
  for (let i = 0; i < CANONICAL_CLASSES.length; i++) {
    if (CANONICAL_CLASSES[i].toLowerCase() === lowerKey) return CANONICAL_CLASSES[i];
  }
  return null;
}

/**
 * Normalise a class to its canonical label.
 * Returns null when the value is unknown or maps to more than one class
 * (e.g. the old grouped "Class 6-8", which cannot be split automatically).
 */
// ─────────────────────────────────────────────────────────────────────────────
// Question types
//
//   CQ  -> creative question     (stem + sub-questions)
//   MCQ -> multiple choice       (text + options + correct answer)
//   RQ  -> short answer question (text + mark)
//
// Rows typed as "SHORT", "SA", "Short Question" etc. are folded to RQ so the app
// can rely on a single code.
// ─────────────────────────────────────────────────────────────────────────────

const CANONICAL_QUESTION_TYPES = ["CQ", "MCQ", "RQ"];

const QUESTION_TYPE_ALIASES = {
  CQ: [],
  MCQ: [],
  RQ: ["short", "shortanswer", "sa", "short question", "shortanswerquestion"],
};

function canonicalizeQuestionType(value) {
  const v = _norm(value);
  if (!v) return null;
  for (let i = 0; i < CANONICAL_QUESTION_TYPES.length; i++) {
    const t = CANONICAL_QUESTION_TYPES[i];
    if (t.toLowerCase() === v) return t;
  }
  for (let i = 0; i < CANONICAL_QUESTION_TYPES.length; i++) {
    const t = CANONICAL_QUESTION_TYPES[i];
    const aliases = QUESTION_TYPE_ALIASES[t] || [];
    for (let j = 0; j < aliases.length; j++) {
      if (aliases[j] === v) return t;
    }
  }
  return null;
}

/**
 * Map any accepted spelling of a class onto its canonical label.
 * Returns null when the value cannot be resolved.
 */
function canonicalizeClass(value) {
  const v = _norm(value);
  if (!v) return null;

  const exact = _canonicalLabel(v);
  if (exact) return exact;

  // Reverse lookup: unambiguous legacy label -> canonical label.
  let found = null;
  for (let i = 0; i < CANONICAL_CLASSES.length; i++) {
    const key = CANONICAL_CLASSES[i].toLowerCase();
    const aliases = LEGACY_CLASS_ALIASES[key] || [];
    if (aliases.indexOf(v) !== -1) {
      if (found) return null; // ambiguous
      found = CANONICAL_CLASSES[i];
    }
  }
  return found;
}

/**
 * Class match for reads: true when the row's class is the requested class, or a
 * legacy label that belongs to it. Never a substring match — that is exactly what
 * made "Class 6" and "Class 7" indistinguishable when the labels were grouped.
 */
function matchesClass(rowClass, filterClass) {
  const rowNorm = _norm(rowClass);
  const fcNorm = _norm(filterClass);
  if (!rowNorm || !fcNorm) return false;
  if (rowNorm === fcNorm) return true;
  return (LEGACY_CLASS_ALIASES[fcNorm] || []).indexOf(rowNorm) !== -1;
}

/** Loose subject match — subjects are free text, so substring is acceptable. */
function matchesSubject(rowSubject, filterSubject) {
  const rs = _norm(rowSubject);
  const fs = _norm(filterSubject);
  if (!rs || !fs) return false;
  return rs === fs || rs.indexOf(fs) !== -1;
}

function rowToObject(row) {
  const obj = {};
  HEADERS.forEach((key, idx) => {
    obj[key] = row[idx] !== undefined ? String(row[idx]) : "";
  });
  // Parse JSON sub_questions safely
  try {
    obj.sub_questions_json = JSON.parse(obj.sub_questions_json);
  } catch (_) {
    obj.sub_questions_json = [];
  }
  return obj;
}

// ─────────────────────────────────────────────────────────────────────────────
// doGet — Fetch questions by class + subject + chapters
//
// Query parameters:
//   action     "getQuestions" (default) | "getChapters"
//   class      (required) e.g. "Class (9-10) SSC"
//   subject    (required) e.g. "Higher Math"
//   chapters   (optional, comma-separated) e.g. "1,3,5"
// ─────────────────────────────────────────────────────────────────────────────

function doGet(e) {
  try {
    const params = e.parameter || {};
    const action        = (params["action"]  || "getQuestions").trim();
    const filterClass   = (params["class"]   || "").trim();
    const filterSubject = (params["subject"] || "").trim();

    if (action === "getChapters") {
      if (!filterClass || !filterSubject) {
        return jsonResponse({ status: "ERROR", message: "Missing class or subject." });
      }
      const chapters = getChaptersForClassSubject(filterClass, filterSubject);
      return jsonResponse({ status: "SUCCESS", data: chapters });
    }

    // ── getQuestions (default) ──────────────────────────────────────────────
    if (!filterClass || !filterSubject) {
      return jsonResponse({
        status: "ERROR",
        message: "Missing required parameters: class and subject.",
      });
    }

    const filterChapters = params["chapters"]
      ? params["chapters"].split(",").map((c) => c.trim())
      : [];

    const sheet   = getSheet();
    const lastRow = sheet.getLastRow();

    if (lastRow <= 1) {
      return jsonResponse({ status: "SUCCESS", count: 0, data: [] });
    }

    const data = sheet
      .getRange(2, 1, lastRow - 1, HEADERS.length)
      .getValues();

    const results = data
      .filter((row) => {
        const rowClass   = row[1];
        const rowSubject = row[2];
        const rowChapter = String(row[3]).trim();

        const classMatch   = matchesClass(rowClass, filterClass);
        const subjectMatch = matchesSubject(rowSubject, filterSubject);
        const chapterMatch =
          filterChapters.length === 0 || filterChapters.includes(rowChapter);

        return classMatch && subjectMatch && chapterMatch;
      })
      .map((row) => rowToObject(row));

    return jsonResponse({
      status: "SUCCESS",
      count: results.length,
      data: results,
    });
  } catch (err) {
    return jsonResponse({ status: "ERROR", message: err.toString() });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// doPost — Upload single or bulk questions
//
// Expected JSON body:
// {
//   "action": "addQuestions",
//   "questions": [
//     {
//       "class": "Class (9-10) SSC",
//       "subject": "উচ্চতর গণিত",
//       "chapter_number": "1",
//       "chapter_name": "সেট ও ফাংশন",
//       "question_type": "CQ",
//       "stem_text": "...",
//       "stem_image_url": "",
//       "sub_questions_json": [...],
//       "board_year_tag": "Dhaka Board 2023"
//     }
//   ]
// }
//
// A short-answer question instead uses:
//   "question_type": "RQ",
//   "stem_text": "সমান্তর সরলরেখার ঢাল কত?",
//   "sub_questions_json": { "text": "সমান্তর সরলরেখার ঢাল কত?", "mark": 2 }
// ─────────────────────────────────────────────────────────────────────────────

function doPost(e) {
  try {
    const rawBody = e.postData.contents;
    const body    = rawBody.replace(/\+/g, ' ');
    const parsed  = JSON.parse(body);
    const action  = parsed.action || "addQuestions";

    if (action !== "addQuestions" && action !== "addBulk") {
      return jsonResponse({ status: "ERROR", message: "Unknown action: " + action });
    }

    const questions = parsed.questions;
    if (!questions || !Array.isArray(questions) || questions.length === 0) {
      return jsonResponse({ status: "ERROR", message: "No questions provided." });
    }

    // Normalise each question's class to a canonical label. Legacy grouped labels
    // ("Class 9-10", …) are migrated on upload so the sheet never accumulates
    // rows the app cannot query. Anything unrecognised is rejected up front.
    const invalid = [];
    const canonicalClasses = questions.map((q, i) => {
      const cls = String((q && q["class"]) || "").trim();
      const canonical = canonicalizeClass(cls);
      if (!canonical) invalid.push('#' + (i + 1) + ' ("' + cls + '")');
      return canonical;
    });
    if (invalid.length > 0) {
      return jsonResponse({
        status: "ERROR",
        message:
          "Invalid class on question(s) " +
          invalid.join(", ") +
          ". Valid values: " +
          CANONICAL_CLASSES.join(" | "),
      });
    }

// Same idea for the question type, so the app only ever sees CQ | MCQ | RQ.
    const badTypes = [];
    const canonicalQuestionTypes = questions.map((q, i) => {
      const raw = String((q && q.question_type) || "").trim();
      const canonical = canonicalizeQuestionType(raw);
      if (!canonical) badTypes.push('#' + (i + 1) + ' ("' + raw + '")');
      return canonical || "CQ";
    });
    if (badTypes.length > 0) {
      return jsonResponse({
        status: "ERROR",
        message:
          "Invalid question_type on question(s) " +
          badTypes.join(", ") +
          ". Valid values: " +
          CANONICAL_QUESTION_TYPES.join(" | ") +
          ' (RQ = short answer question).',
      });
    }

    // ── Duplicate id check ────────────────────────────────────────────────
    //
    // The script is the authority for identity: any row without an id gets a
    // fresh UUID here, and a client-supplied id is treated as an idempotency
    // key. Re-uploading the same queue therefore cannot create duplicate rows.
    //
    // Policy: reject the WHOLE batch if any supplied id is already used, either
    // elsewhere in this batch or by an existing row. Nothing is written.
    const sheet = getSheet();
    const existingIds = readExistingIds(sheet);
    const seenInBatch = Object.create(null);
    const duplicates = [];

    questions.forEach((q, i) => {
      const raw = String((q && q.id) || "").trim();
      if (!raw) return; // server will generate one

      const key = raw.toLowerCase();
      if (seenInBatch[key]) {
        duplicates.push(raw + " (repeated in this upload)");
        return;
      }
      seenInBatch[key] = true;
      if (existingIds[key]) {
        duplicates.push(raw + " (already in sheet)");
      }
    });

    if (duplicates.length > 0) {
      return jsonResponse({
        status: "ERROR",
        message:
          "Duplicate question id — nothing was uploaded: " +
          duplicates.join(", ") +
          ". Each question must have a unique id. Remove the duplicate(s) " +
          "from the queue and try again.",
      });
    }

    const rows = questions.map((q, i) => {
      const subJson =
        typeof q.sub_questions_json === "string"
          ? q.sub_questions_json
          : JSON.stringify(q.sub_questions_json || []);

      return [
        q.id              || generateId(),
        canonicalClasses[i],
        q.subject         || "",
        String(q.chapter_number || ""),
        q.chapter_name    || "",
        canonicalQuestionTypes[i],
        q.stem_text       || "",
        q.stem_image_url  || "",
        subJson,
        q.board_year_tag  || "",
      ];
    });

    // Bulk-append all rows in one call
    sheet
      .getRange(sheet.getLastRow() + 1, 1, rows.length, HEADERS.length)
      .setValues(rows);

    return jsonResponse({
      status: "SUCCESS",
      message: `${rows.length} question(s) added successfully.`,
      inserted: rows.length,
    });
  } catch (err) {
    return jsonResponse({ status: "ERROR", message: err.toString() });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: return unique chapters for a class+subject combo
// ─────────────────────────────────────────────────────────────────────────────

function getChaptersForClassSubject(filterClass, filterSubject) {
  const sheet   = getSheet();
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return [];

  const data = sheet
    .getRange(2, 1, lastRow - 1, HEADERS.length)
    .getValues();

  const chaptersMap = {};
  data.forEach((row) => {
    if (
      matchesClass(row[1], filterClass) &&
      matchesSubject(row[2], filterSubject)
    ) {
      const num  = String(row[3]).trim();
      const name = String(row[4]).trim();
      if (num) chaptersMap[num] = name;
    }
  });

  return Object.entries(chaptersMap)
    .sort((a, b) => Number(a[0]) - Number(b[0]))
    .map(([num, name]) => ({ chapter_number: num, chapter_name: name }));
}
