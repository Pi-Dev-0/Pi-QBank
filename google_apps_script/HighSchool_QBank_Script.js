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
 *  F  = question_type  (CQ | MCQ)
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

function jsonResponse(data) {
  const payload = JSON.stringify(data);
  return ContentService.createTextOutput(payload)
    .setMimeType(ContentService.MimeType.JSON);
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
//   class      (required) e.g. "Class 9-10"
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
      const chapters = getChaptersForClassSubject(
        filterClass.toLowerCase(),
        filterSubject.toLowerCase()
      );
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

    const fcLower = filterClass.toLowerCase();
    const fsLower = filterSubject.toLowerCase();

    const results = data
      .filter((row) => {
        const rowClass   = String(row[1]).trim().toLowerCase();
        const rowSubject = String(row[2]).trim().toLowerCase();
        const rowChapter = String(row[3]).trim();

        const classMatch   = rowClass === fcLower || rowClass.includes(fcLower);
        const subjectMatch = rowSubject === fsLower || rowSubject.includes(fsLower);
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
//       "class": "Class 9-10",
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
// ─────────────────────────────────────────────────────────────────────────────

function doPost(e) {
  try {
    const body   = JSON.parse(e.postData.contents);
    const action = body.action || "addQuestions";

    if (action !== "addQuestions" && action !== "addBulk") {
      return jsonResponse({ status: "ERROR", message: "Unknown action: " + action });
    }

    const questions = body.questions;
    if (!questions || !Array.isArray(questions) || questions.length === 0) {
      return jsonResponse({ status: "ERROR", message: "No questions provided." });
    }

    const sheet = getSheet();

    const rows = questions.map((q) => {
      const subJson =
        typeof q.sub_questions_json === "string"
          ? q.sub_questions_json
          : JSON.stringify(q.sub_questions_json || []);

      return [
        q.id              || generateId(),
        q["class"]        || "",
        q.subject         || "",
        String(q.chapter_number || ""),
        q.chapter_name    || "",
        q.question_type   || "CQ",
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

function getChaptersForClassSubject(fcLower, fsLower) {
  const sheet   = getSheet();
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return [];

  const data = sheet
    .getRange(2, 1, lastRow - 1, HEADERS.length)
    .getValues();

  const chaptersMap = {};
  data.forEach((row) => {
    const rowClass   = String(row[1]).trim().toLowerCase();
    const rowSubject = String(row[2]).trim().toLowerCase();
    if (
      (rowClass === fcLower || rowClass.includes(fcLower)) &&
      (rowSubject === fsLower || rowSubject.includes(fsLower))
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
