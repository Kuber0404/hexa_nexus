# Final report (LaTeX)

English course report for SD6103 Data Systems (AY26S1), team Hexa Nexus.

## Build

From this directory:

```bash
latexmk -pdf -interaction=nonstopmode main.tex
```

Or:

```bash
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

Output: `main.pdf`.

Requirements: a TeX distribution with `pdflatex`, `bibtex`/`latexmk`, and common packages (`geometry`, `graphicx`, `booktabs`, `hyperref`, `listings`, `natbib`, `pdflscape`, \ldots). No `-shell-escape` is required.

## Layout

| Path | Content |
|---|---|
| `main.tex` | Preamble, title page, includes |
| `chapters/` | Introduction through AI declaration |
| `appendix/` | Schema SQL, queries, index SQL, artefact checklist |
| `figures/` | Self-contained copies of ER, screenshots, charts |
| `sql/` | Copies of `schema.sql`, `queries.sql`, `indexes.sql` |
| `refs.bib` | Data-source references |

## Team must fill before submission

Search the PDF/source for `[[TODO:`:

- Official submission date on the title page
- AI declaration: tools used, purposes, human verification scope, optional reflection

## Numbers

Task 3/4 tables were taken from the repository CSVs current as of the draft date.
If experiments are re-run, update the corresponding chapter tables and recompile.
