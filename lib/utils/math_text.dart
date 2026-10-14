/// LaTeX-lite parsing for maths question text.
///
/// Question banks author their maths in LaTeX (`\frac{a}{b}`, `$x^2$`), so the
/// app has to understand that notation rather than print it. This file turns
/// LaTeX into a small set of segments; the PDF renderer, the measurer and the
/// HTML/Word/plain-text writers each render those segments their own way.
///
/// Everything is parsed **once, when the question is loaded**, so the preview
/// and every export format show the same thing.
library;

// ─────────────────────────────────────────────────────────────────────────────
// Segments
// ─────────────────────────────────────────────────────────────────────────────

/// One piece of a question's text.
sealed class MathSegment {
  const MathSegment();

  /// True when this piece sat inside `$...$`, so Latin letters are maths
  /// variables and should be set in italic.
  bool get isMath => false;
}

/// Ordinary text.
class MathText extends MathSegment {
  const MathText(this.text, {this.math = false});
  final String text;

  /// True when this piece sat inside `$...$`.
  final bool math;

  @override
  bool get isMath => math;

  @override
  String toString() => text;
}

/// A fraction the author asked to be typeset: `\frac{a}{b}`.
///
/// An explicit marker rather than a heuristic: `(x+2)/3` in a question bank is
/// far more often an inline division than a stacked fraction, and guessing
/// wrong silently rewrites the maths.
class MathFraction extends MathSegment {
  const MathFraction(this.numerator, this.denominator, {this.math = false});
  final String numerator;
  final String denominator;

  /// True when this piece sat inside `$...$`.
  final bool math;

  @override
  bool get isMath => math;

  @override
  String toString() => '($numerator)/($denominator)';
}

/// A super- or subscript: `x^{2}`, `a_{n}`.
class MathScript extends MathSegment {
  const MathScript(this.text, {required this.superscript, this.math = false});
  final String text;

  /// True for `^`, false for `_`.
  final bool superscript;

  /// True when this piece sat inside `$...$`.
  final bool math;

  @override
  bool get isMath => math;

  @override
  String toString() => superscript ? '^$text' : '_$text';
}

// ─────────────────────────────────────────────────────────────────────────────
// Symbol table
// ─────────────────────────────────────────────────────────────────────────────

/// LaTeX commands that stand for a single character.
const Map<String, String> kLatexSymbols = {
  'times': '×', 'div': '÷', 'pm': '±', 'mp': '∓', 'cdot': '·', 'ast': '∗',
  'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥', 'neq': '≠', 'ne': '≠',
  'approx': '≈', 'equiv': '≡', 'propto': '∝', 'sim': '∼', 'simeq': '≃',
  'infty': '∞', 'partial': '∂', 'nabla': '∇', 'forall': '∀', 'exists': '∃',
  'in': '∈', 'notin': '∉', 'ni': '∋', 'subset': '⊂', 'subseteq': '⊆',
  'supset': '⊃', 'supseteq': '⊇', 'cup': '∪', 'cap': '∩', 'emptyset': '∅',
  'varnothing': '∅', 'circ': '∘', 'bullet': '•', 'oplus': '⊕',
  'otimes': '⊗', 'angle': '∠', 'perp': '⊥', 'parallel': '∥', 'degree': '°',
  'to': '→', 'rightarrow': '→', 'Rightarrow': '⇒', 'leftarrow': '←',
  'Leftarrow': '⇐', 'leftrightarrow': '↔', 'mapsto': '↦', 'ldots': '…',
  'dots': '…', 'cdots': '⋯', 'therefore': '∴', 'because': '∵',
  'sum': '∑', 'prod': '∏', 'int': '∫', 'alpha': 'α', 'beta': 'β',
  'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
  'theta': 'θ', 'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ',
  'nu': 'ν', 'xi': 'ξ', 'pi': 'π', 'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ',
  'upsilon': 'υ', 'phi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  'Delta': 'Δ', 'Sigma': 'Σ', 'Omega': 'Ω', 'Theta': 'Θ', 'Pi': 'Π',
  // Plain-TeX aliases that also show up in textbooks.
  'le ': '≤', 'ge ': '≥',
};

/// Commands that take one `{...}` group and mean "upright text".
const Set<String> kTextCommands = {
  'text',
  'mathrm',
  'textbf',
  'mbox',
  'operatorname'
};

/// Commands that are pure spacing.
const Map<String, String> kSpacingCommands = {
  'quad': '   ',
  'qquad': '     ',
  ',': ' ',
  ';': '  ',
  ':': ' ',
  '!': '',
  ' ': ' ',
  'thinspace': ' ',
  'enspace': '  ',
};

// ─────────────────────────────────────────────────────────────────────────────
// Fractions with a ready-made glyph
// ─────────────────────────────────────────────────────────────────────────────

/// Fractions with a standard single-character glyph, keyed by `n/d`.
///
/// Used for bare `1/2` typed without LaTeX. `4/7` has no glyph and building it
/// from stacked digits looks worse, so it stays exactly as typed.
const Map<String, String> kVulgarFractions = {
  '1/2': '½',
  '1/3': '⅓',
  '2/3': '⅔',
  '1/4': '¼',
  '3/4': '¾',
  '1/5': '⅕',
  '2/5': '⅖',
  '3/5': '⅗',
  '4/5': '⅘',
  '1/6': '⅙',
  '5/6': '⅚',
  '1/8': '⅛',
  '3/8': '⅜',
  '5/8': '⅝',
  '7/8': '⅞',
};

// ─────────────────────────────────────────────────────────────────────────────
// Parser
// ─────────────────────────────────────────────────────────────────────────────

/// Parse [text] into plain text, fractions, scripts and symbols.
///
/// Tolerant by design: an unknown command or an unbalanced brace is emitted
/// literally rather than swallowing the rest of the question, because a
/// question that prints slightly wrong is recoverable and one that prints
/// nothing is not.
List<MathSegment> parseMath(String text) {
  if (text.isEmpty) return const [];

  final out = <MathSegment>[];
  final buffer = StringBuffer();
  var math = false; // inside $...$

  void flush() {
    if (buffer.isEmpty) return;
    out.add(MathText(buffer.toString(), math: math));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    final c = text[i];

    // ── escaped LaTeX commands ──────────────────────────────────────────
    if (c == r'\' && i + 1 < text.length) {
      final next = text[i + 1];

      if (next == r'\') {
        buffer.write(' ');
        i += 2;
        continue;
      }

      // A command is a run of letters, or a single non-letter such as `\,`.
      var name = next;
      var cursor = i + 1;
      if (_isLetter(next)) {
        while (cursor < text.length && _isLetter(text[cursor])) {
          cursor++;
        }
        name = text.substring(i + 1, cursor);
      } else {
        cursor = i + 2;
      }

      switch (name) {
        case 'frac':
          final num = _readGroup(text, cursor);
          if (num != null) {
            final den = _readGroup(text, num.end);
            if (den != null) {
              flush();
              out.add(MathFraction(num.body, den.body, math: math));
              i = den.end;
              continue;
            }
          }
          buffer.write(text.substring(i, cursor));
          i = cursor;

        case 'sqrt':
          buffer.write('√');
          final arg = _readGroup(text, cursor);
          if (arg != null) {
            buffer.write(arg.body);
            i = arg.end;
          } else {
            i = cursor;
          }

        case 'left':
        case 'right':
          // Purely a delimiter-sizing hint; the delimiter itself is the next
          // character and is kept as ordinary text.
          i = cursor;

        case 'quad':
        case 'qquad':
        case ',':
        case ';':
        case ':':
        case '!':
        case ' ':
          buffer.write(kSpacingCommands[name]);
          i = cursor;

        default:
          if (kTextCommands.contains(name)) {
            final arg = _readGroup(text, cursor);
            if (arg != null) {
              flush();
              out.add(MathText(arg.body));
              i = arg.end;
            } else {
              buffer.write(text.substring(i, cursor));
              i = cursor;
            }
          } else {
            final symbol = kLatexSymbols[name];
            if (symbol != null) {
              flush();
              out.add(MathText(symbol, math: true));
              i = cursor;
            } else {
              // Unknown command: keep it visible rather than losing it.
              buffer.write(text.substring(i, cursor));
              i = cursor;
            }
          }
      }
      continue;
    }

    // ── inline math delimiter ───────────────────────────────────────────
    if (c == r'$') {
      // Flush before switching, or the run inside the delimiters would be
      // tagged with the mode it left in rather than the one it was in.
      flush();
      math = !math;
      i++;
      continue;
    }

    // ── super/subscript ────────────────────────────────────────────────
    //
    // Only inside `$...$`. Outside it these are ordinary characters: `^` turns
    // up in prose and in identifiers, and quietly typesetting the next word as
    // a raised script loses it. `\frac` is deliberately *not* restricted this
    // way, because question banks write it without delimiters.
    if ((c == '^' || c == '_') && i + 1 < text.length) {
      final arg = _readGroup(text, i + 1);
      final body = arg?.body ?? (i + 2 <= text.length ? text[i + 1] : '');
      if (arg != null) {
        if (math) {
          flush();
          out.add(MathScript(body, superscript: c == '^', math: true));
        } else {
          // Kept exactly as written, braces and all, so nothing disappears.
          buffer
            ..write(c)
            ..write('{$body}');
        }
        i = arg.end;
      } else if (i + 2 <= text.length) {
        if (math) {
          flush();
          out.add(MathScript(body, superscript: c == '^', math: true));
        } else {
          buffer
            ..write(c)
            ..write(body);
        }
        i += 2;
      } else {
        buffer.write(c);
        i++;
      }
      continue;
    }

    buffer.write(c);
    i++;
  }

  flush();
  return out;
}

bool _isLetter(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}

/// Read a `{...}` group at [start], honouring nesting.
///
/// Returns the inner text and the index just past the closing brace, or null
/// when there is no balanced group there.
({String body, int end})? _readGroup(String text, int start) {
  if (start >= text.length || text[start] != '{') return null;
  var depth = 0;
  final body = StringBuffer();
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (c == '{') {
      depth++;
      if (depth == 1) continue;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return (body: body.toString(), end: i + 1);
    }
    body.write(c);
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple typed fractions
// ─────────────────────────────────────────────────────────────────────────────

/// A single digit over a single digit: `1/2`.
///
/// Guards keep it away from expressions that only look like a fraction:
/// `[^\d)\]]` before the numerator, so `12/3` and `(2-x)/3` are untouched, and
/// a word boundary, so `a1/2` and `x/2` are left alone.
final RegExp _simpleFraction = RegExp(r'(?<![\d)\]])\b(\d)\/(\d)\b');

/// Turn bare typed fractions into their glyph: `1/2` becomes `½`.
///
/// Only single digits on both sides are converted, and only where a glyph
/// exists, so algebraic fractions such as `(2-x)/3` and `4(x+1)/7` keep their
/// digits exactly as typed.
String normaliseTypedFractions(String text) =>
    text.replaceAllMapped(_simpleFraction, (m) {
      final glyph = kVulgarFractions['${m.group(1)}/${m.group(2)}'];
      return glyph ?? m.group(0)!;
    });

// ─────────────────────────────────────────────────────────────────────────────
// Plain-text form
// ─────────────────────────────────────────────────────────────────────────────

/// Flatten segments to plain text, for outputs that cannot typeset.
///
/// Word and the plain-text export get `(x+2)/3` and `x^2` — unambiguous and
/// editable, where a drawing would be neither.
String mathToPlainText(List<MathSegment> segments) =>
    segments.map((s) => s.toString()).join();

/// Parse and flatten in one step.
String latexToPlainText(String text) => mathToPlainText(parseMath(text));

/// True when [text] contains anything worth typesetting.
bool hasTypesetMath(String text) {
  for (final s in parseMath(text)) {
    if (s is MathFraction || s is MathScript) return true;
  }
  return false;
}
// ─────────────────────────────────────────────────────────────────────────────
// Typesetting metrics
// ─────────────────────────────────────────────────────────────────────────────
//
// Shared by the PDF renderer and the layout estimator. They live here rather
// than in pdf_column_layout so the renderer can use them without importing it,
// which would close a cycle through the measurer.

/// Size of a typeset fraction's numerator and denominator, as a fraction of
/// the surrounding font size.
const double fracFontScale = 0.72;

/// Thickness of the rule between a fraction's numerator and denominator.
const double fracRuleHeight = 0.5;

/// Space either side of a typeset fraction, so it does not touch its
/// neighbours.
const double fracPaddingX = 1.5;

/// Size of a super/subscript, as a fraction of the surrounding font size.
const double scriptFontScale = 0.68;

/// How far a superscript rises, as a fraction of the surrounding font size.
/// Positive is up.
const double superscriptRise = 0.33;

/// How far a subscript drops.
const double subscriptDrop = 0.14;

/// How far a typeset fraction is dropped below the text baseline, as a
/// fraction of the surrounding font size.
///
/// The pdf package anchors an inline widget by its **bottom**, so with no shift
/// the whole stack floats above the line and the rule ends up level with the
/// tops of the letters. Dropping it by about half a stack puts the rule on the
/// maths axis, where a fraction belongs.
const double fracBaselineShift = 0.62;

// ─────────────────────────────────────────────────────────────────────────────
// HTML
// ─────────────────────────────────────────────────────────────────────────────

/// Render segments as HTML.
///
/// A fraction becomes nested spans with the `frac` class; the stylesheet in the
/// export supplies the stacking and the rule. Only the structural tags are
/// emitted here — the caller escapes the surrounding prose.
String mathToHtml(List<MathSegment> segments) {
  final out = StringBuffer();
  for (final segment in segments) {
    switch (segment) {
      case MathFraction(:final numerator, :final denominator):
        out.write('<span class="frac">'
            '<span class="frac-num">$numerator</span>'
            '<span class="frac-den">$denominator</span>'
            '</span>');
      case MathScript(:final text, :final superscript):
        out.write(superscript ? '<sup>$text</sup>' : '<sub>$text</sub>');
      case MathText(:final text, :final math):
        out.write(math ? '<span class="mathv">$text</span>' : text);
    }
  }
  return out.toString();
}

/// Parse and render as HTML in one step.
String latexToHtml(String text) => mathToHtml(parseMath(text));

/// The CSS the HTML export needs for the classes [mathToHtml] emits.
const String kMathCss =
    '.frac { display:inline-block; vertical-align:middle; text-align:center; margin:0 .15em; line-height:1.05; }'
    '.frac .frac-num { display:block; padding:0 .25em; border-bottom:1px solid #000; }'
    '.frac .frac-den { display:block; padding:0 .25em; }'
    '.mathv { font-style:italic; }';
