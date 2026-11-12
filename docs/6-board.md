# Board runbook

What the board does when someone reports a study. A study goes public at once and nobody reads it first, so
this page is the safety net. Read it from top to bottom once, then use the commands. It is written to be
followed at 2 a.m.

Every command below runs as root on the host, with the variables of the unit. Write them once:

```bash
M='sudo env MAROLA_DB=/var/lib/marola/marola.db MAROLA_STUDIES=/var/lib/marola/studies /opt/marola/server/bin/marola-server'
```

Then `$M reports --open` is the first command. The commands print plain lines. Text that a visitor wrote is
printed with every control character turned into a space, so it cannot change your terminal.

**Exit codes.** `0` done. `1` nothing changed (no such study, it is in that state already, or the command is
refused; the message says why). `2` wrong usage (a missing option, a reason that is too short; the usage is
printed).

## 1. Read the reports

```bash
$M reports --open        # reports nobody has closed
$M reports               # all of them, with the note of the closed ones
```

Each report is two lines: `#<report-id>  <time>  study <study-id>  open`, then the text of the reporter,
indented. A report has no name, no address and no account: there is nobody to write back to. The reporter may
have left nothing but a reason from the list.

Then look at the study. Open `https://marola.dev/studies/<study-id>` in a browser (or `/en/studies/<study-id>`),
and read its title, its abstract and its PDF. To see all studies and how many reports each has:

```bash
$M studies list                    # the 50 newest, any status
$M studies list --status hidden    # what is hidden now, with the reasons
$M studies list --status public --limit 200
```

A line shows: id, status, time, area and topic, number of reports, author login, title. A hidden study also
shows when it was hidden and why.

## 2. Decide

Hide first when the report is credible and the harm is real. You can show a study again; you cannot undo what
people read in the meantime. Ask questions later.

| The report says | Do |
|---|---|
| A person is named and accused, or a private fact is published | Hide now. Purge the file if the claim holds (step 3) |
| A health or water claim that is plainly wrong and could hurt a swimmer | Hide now |
| Copied work, or a file the author may not publish | Hide now; purge if the owner of the work asks |
| Hate, threats, spam, adverts | Hide now |
| "I do not agree with the result" | Do not hide. Close the report with a note |
| You cannot tell | Hide, and write why in the reason. Unhide later if you were wrong |

Two board members agree on a purge when time allows. At night, one member may hide; a purge can wait for the
day, because a hidden study is already not served.

## 3. Hide

```bash
$M studies hide <study-id> --reason "<why, 5 to 300 characters>"
```

The reason is shown to everyone on the tombstone page and in the API. Write it for a reader: plain, no names
of people, no copy of the claim. Good: `reported as defamation, under review`. Bad: the text of the claim.

What happens: the study leaves the list and the feed. Its page shows a tombstone with
the id, the hash, the date and the reason. Its PDF is no longer served. The file stays on disk and the row
stays in the database.

To delete the file as well (a legal order, a private fact, a copy of a work):

```bash
$M studies hide <study-id> --reason "removed on request of the rights holder" --purge
```

`--purge` deletes the PDF and keeps the row, the hash and the reason. It prints a line that starts with
`purged`. **Copy that line into the board's record** (date, study id, hash, who decided, why). A restore of a
backup brings the file back (see [the hosting page](5-hosting.md#the-studies-and-their-backup)), and the
record tells you which files to delete again.

If another public study has the same file (two authors sent the same bytes), the purge is refused and the
message names the other study. Hide that one too, then purge. Nothing changes when a purge is refused.

If the study is hidden already, `--purge` alone with a reason still deletes the file; the old reason stays.

## 4. Answer

The reporter cannot be answered. The author can: the author's GitHub login is on the study record
(`$M studies list` shows it), and a GitHub account has a public profile. Write to the author only if the
report needs it. Never write the reporter's text into a public place.

Then close the report, with a note for the next member:

```bash
$M reports close <report-id> --note "hidden, author asked to fix the claim"
$M reports close <report-id> --note "no action: a disagreement about the method"
```

A note has 3 to 300 characters. A report that is closed cannot be closed again.

## 5. Undo

```bash
$M studies unhide <study-id>
```

It shows the study again and clears the reason. It is refused when the file was purged (nothing to show) and
when the author deleted the account (the author asked for it to go). Close or note the report either way.

## 6. A person asks to delete their data

The author does it alone at `/account`: the button "Delete my account" removes the keys, the sessions and the
account, hides the studies with the reason `account deleted by the author` and detaches them from the person.
The rows and the files stay, and the files are not served. If the person also wants the files gone, that is a
board decision: find the studies with `$M studies list --status hidden`, then purge each (step 3). Say in the
record who decided.

A person who does not have a GitHub login any more, or who cannot reach the page, writes to the contact address
of the site. The board checks the claim and runs the same steps.

## 7. What not to do

- Do not edit `marola.db` with `sqlite3`. The commands above keep the rows right.
- Do not delete a file under `MAROLA_STUDIES` by hand. Use `--purge`, so the row knows the file is gone.
- Do not copy the text of a report into an issue, a chat or an email.
- Do not skip the record of a purge.
