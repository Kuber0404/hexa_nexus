# Data Systems Project — What This Is About

**SD6103 Data Systems** · AY26S1 · Prof. Melanie Herschel · Team of 6

> 📋 For the task breakdown, dependencies, owners and timeline, see **[PROJECT_PLAN.md](PROJECT_PLAN.md)**.

---

## The story

Singapore has two things everyone cares about: **HDB flats** (where people live) and **hawker centres** (where people eat cheap).

Someone hands us a pile of messy spreadsheets from data.gov.sg and asks a simple question:

> *"Do flats near a hawker centre sell for more than flats far from one?"*

Our job is to **build the database that can answer that** — and then prove it works and prove it's fast.

That's the whole project. Four tasks, which are really just the four normal steps of building any data system.

---

## Task 1 — Design the boxes (25%)

Before touching any data, we draw a picture of what we're storing.

There are four things in the real world: **Towns**, **Flats**, **Sales**, and **Hawker centres**. We draw them as boxes and draw lines showing how they connect — a Town *contains* many Flats, a Flat *has* many Sales, a Flat is *near* some Hawker centres.

Then we decide what **"near"** means. The prof deliberately doesn't tell us — we invent three levels ourselves:

| Class | Distance |
|---|---|
| NEAR | under 500 m |
| MEDIUM | 500 m – 1 km |
| FAR | 1 km – 2 km |

Finally we turn that drawing into actual `CREATE TABLE` commands in PostgreSQL, with rules so nobody can put garbage in (no negative prices, no flat sizes of zero, no sale pointing at a flat that doesn't exist).

**Deliverable:** an ER diagram + a `.sql` file.

---

## Task 2 — Get the real data in (10%)

Now the messy part. The raw files don't match our clean design:

- The resale files **don't have coordinates** → we get those from a different file and match them up by address
- The hawker file with coordinates **doesn't say which ones have market stalls** → that's in another file, matched by name
- **Nobody gives us distances** → we calculate them ourselves (every flat vs every hawker centre, keep the ones under 2 km)
- One column exists in some files and not others, and where it does exist it's written as text like `"61 years 04 months"`

So we write a Python script that reads the raw junk, cleans it, computes the distances, and spits out one tidy CSV per table. Then we bulk-load those into Postgres.

The prof explicitly says: **we will get errors, and writing down what broke is part of the grade.** So keep a log as we go.

**Deliverable:** the script + a written reflection on what broke.

---

## Task 3 — Ask questions, then time them (25%)

### Part A — write 6 queries

Five are given:

| | Question |
|---|---|
| **Q1** | Average price per square metre by town, for 4- and 5-Room flats |
| **Q2** | Price vs how much lease is left |
| **Q3** | Which towns have the biggest 3-Room flats, and what sold highest there |
| **Q4** | The near-vs-far hawker price gap |
| **Q5** | Towns near hawkers that have fresh market stalls |
| **Q6** | *Our own invention* — must touch every table |

For each one we also write down **one thing we learned** from the answer. *"Turns out being near a hawker centre makes no difference"* is a perfectly good finding.

### Part B — the science experiment

This is the bit people underestimate.

We start with **one** of the five resale files loaded. Run all 6 queries, 5 times each, write down how many milliseconds each took. Then add a second file and do it all again. Then a third. Then a fourth. Then a fifth.

```
6 queries × 5 runs × 5 database sizes = 150 numbers
```

Plot them on a graph. Does doubling the data double the time? Or does one query suddenly fall off a cliff?

**Deliverable:** the queries, screenshots of results, a spreadsheet of 150 timings, and a chart.

---

## Task 4 — Make it fast (20%)

Some of those queries will be slow. We ask Postgres *"why?"* using `EXPLAIN`, and it shows us it's reading the entire table every time.

So we add **indexes** — basically the index at the back of a textbook, so the database can jump straight to the right rows instead of reading all of them.

Then we re-time everything on the full database and draw a before/after bar chart.

The key thing: **we must explain *why* we added each index.** Randomly adding indexes and hoping scores badly. And we should also report the ones that **didn't** help — that's the interesting part.

**Deliverable:** the `CREATE INDEX` statements + bar chart + discussion.

---

## Then the viva (15%)

15 minutes, all 6 of us in a room, on site. The prof can ask **anyone** about **any part** — including the parts you personally didn't write.

That's why the plan rotates people across phases instead of letting one person own ETL forever. *"That was Bob's bit"* is not an answer that scores.

---

## The one-sentence version

> **Design a database, stuff real Singapore housing data into it, ask it six questions, and then prove with measurements that we made it fast.**

The technical skills are ordinary. What's actually being tested is whether we **make deliberate choices and can defend them** — the brief literally says it's *"ambiguous by design"* to see if we'll pick a lane and justify it.

---

## Repo contents

| File | What it is |
|---|---|
| `Data Systems Project.pdf` | The official brief from the prof |
| `hawker_geo.csv` | Hawker centre coordinates (129 rows, provided on NTULearn) |
| `PROJECT_PLAN.md` | Task breakdown, dependency graph, owners, timeline |
| `README.md` | This file |
