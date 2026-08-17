# Vendored KaTeX 0.18.4

`katex.min.js`, `katex.min.css`, and the woff2 fonts from the `katex` npm
package, unmodified. Vendored so the local server works offline with no
CDN; only the woff2 fonts are kept (every current browser loads them, and
the stylesheet lists them first).

Used for presentation only: pages typeset the LaTeX the OCaml core emits.
No mathematics is computed in the browser.
