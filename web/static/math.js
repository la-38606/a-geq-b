// Typesets every element carrying a data-latex attribute with the vendored
// KaTeX. Presentation only: the LaTeX strings come from the OCaml core, and
// the attribute is left in place so tests can assert the mathematics rather
// than the rendered markup.
'use strict';

function tex(el, latex, display) {
  el.dataset.latex = latex;
  katex.render(latex, el, { throwOnError: false, displayMode: !!display });
}

function typeset(root) {
  for (const el of (root || document).querySelectorAll('[data-latex]')) {
    if (el.dataset.latex !== '') {
      tex(el, el.dataset.latex, el.hasAttribute('data-display'));
    }
  }
}

typeset(document);
