"""Bronings weekly waiting list exception report — scheduled version of
Waiting_List_Exception_Report.ipynb. Run: python run_weekly_report.py
Schedule: Monday 07:00 (Task Scheduler / cron)."""

from pathlib import Path
from datetime import datetime
import pandas as pd
import numpy as np

DATA_DIR   = Path("data")          # folder holding the five CSV extracts
OUTPUT_DIR = Path("output")        # where the Excel report is written
OUTPUT_DIR.mkdir(exist_ok=True)

FILES = {
    "Outpatients": "03_outpatient_appointments.csv",
    "Inpatients":  "04_inpatient_admissions.csv",
    "ED":          "05_ed_attendances.csv",
    "Theatres":    "06_theatre_utilisation.csv",
    "Workforce":   "07_workforce_staffing.csv",
}

VALID_STATUS      = ["ATT", "DNA", "CAN", "REF"]     # DNA denominator (KPI Framework, KPI 3)
STATUS_FIXES      = {"ATTENDED": "ATT"}             # known non-standard spellings -> standard code
RETIRED_SPECIALTY = {"GEN": "GM"}                   # GEN retired; mapped to General Medicine
DNA_TARGET        = 8.0     # % — Trust target
DNA_RED           = 15.0    # % — specialty flagged Red above this
RTT_STANDARD      = 92.0    # % — NHS Constitution
RTT_WEEKS_LIMIT   = 18
DQ_GREEN, DQ_AMBER = 95.0, 85.0                     # DSP Toolkit / Task 14 thresholds

RUN_TIME = datetime.now()
pd.set_option("display.width", 160)
pd.set_option("display.max_columns", 20)
print(f"Run started {RUN_TIME:%d/%m/%Y %H:%M:%S}")

def load(name):
    df = pd.read_csv(DATA_DIR / FILES[name], dtype=str, keep_default_na=False)
    df = df.apply(lambda s: s.str.strip())          # remove stray spaces
    return df

raw = {name: load(name) for name in FILES}
op_raw = raw["Outpatients"]

pd.DataFrame({"rows": {k: len(v) for k, v in raw.items()},
              "columns": {k: v.shape[1] for k, v in raw.items()}})

op = op_raw.copy()
clean_log = []
def log(rule, mask, note):
    clean_log.append({"Rule": rule, "Rows affected": int(mask.sum()), "Action": note})

# Dates
op["Appointment_Date"] = pd.to_datetime(op["Appointment_Date"], format="%d/%m/%Y", errors="coerce")

# C1 / C2 — attendance status
op["Attendance_Status_Raw"] = op["Attendance_Status"]
status_up = op["Attendance_Status"].str.upper().replace(STATUS_FIXES)
log("C1", op["Attendance_Status"].str.upper().isin(STATUS_FIXES.keys()), "Non-standard spelling mapped to ATT")
op["Attendance_Status"] = status_up
op["Valid_Status"] = op["Attendance_Status"].isin(VALID_STATUS)
log("C2", ~op["Valid_Status"], "Non-standard status (e.g. N/A) excluded from DNA denominator")

# C3 — blank NHS Number
op["No_NHS_Number"] = op["NHS_Number"].eq("")
log("C3", op["No_NHS_Number"], "Blank NHS Number flagged — listed as exception")

# C4 / C5 — waiting days
op["RTT_Weeks"] = pd.to_numeric(op["RTT_Weeks"], errors="coerce")
wd = pd.to_numeric(op["Waiting_Days"], errors="coerce")
text_wd = wd.isna() & op["Waiting_Days"].ne("")
neg_wd = wd < 0
log("C4", text_wd, "Text in Waiting_Days recovered as RTT_Weeks x 7")
log("C5", neg_wd, "Negative Waiting_Days set to blank")
wd = wd.where(~text_wd, (op["RTT_Weeks"] * 7).round())
op["Waiting_Days"] = wd.where(~neg_wd)

# C6 / C7 — RTT status
blank_rtt = op["RTT_Status"].eq("") & op["RTT_Weeks"].notna()
log("C6", blank_rtt, "Blank RTT_Status with weeks recorded -> OPEN")
op.loc[blank_rtt, "RTT_Status"] = "OPEN"
no_clock = op["RTT_Status"].eq("OPEN") & op["RTT_Weeks"].isna()
log("C7", no_clock, "OPEN pathway with no RTT_Weeks — not measurable")
op["Measurable_Open"] = op["RTT_Status"].eq("OPEN") & op["RTT_Weeks"].notna()

# C8 — retired specialty code
log("C8", op["Specialty_Code"].isin(RETIRED_SPECIALTY.keys()), "Retired specialty GEN mapped to GM")
op["Specialty_Code"] = op["Specialty_Code"].replace(RETIRED_SPECIALTY)

# One DQ flag text per row (used in the exception lists)
flags = {
    "NO_NHS_NUMBER": op["No_NHS_Number"],
    "NON_STANDARD_STATUS": ~op["Valid_Status"],
    "WAITING_DAYS_REPAIRED": text_wd | neg_wd,
    "NO_RTT_CLOCK": no_clock,
}
op["DQ_Flag"] = pd.DataFrame(flags).apply(lambda r: "; ".join(k for k, v in r.items() if v), axis=1)

clean_log = pd.DataFrame(clean_log)

valid = op[op["Valid_Status"]]
dna_rate = (valid["Attendance_Status"].eq("DNA").sum() / len(valid)) * 100

open_p   = op[op["Measurable_Open"]]
breaches = open_p[open_p["RTT_Weeks"] > RTT_WEEKS_LIMIT]
rtt_compliance = (1 - len(breaches) / len(open_p)) * 100

kpi = pd.DataFrame([
    ("Appointments in extract",               len(op),                       ""),
    ("Appointments with a valid status",      len(valid),                    "ATT + DNA + CAN + REF"),
    ("DNAs",                                  int(valid["Attendance_Status"].eq("DNA").sum()), ""),
    ("DNA rate %",                            round(dna_rate, 2),            f"Target {DNA_TARGET}%"),
    ("Measurable open RTT pathways",          len(open_p),                   ""),
    ("RTT breaches (>18 weeks)",              len(breaches),                 ""),
    ("RTT compliance %",                      round(rtt_compliance, 2),      f"Standard {RTT_STANDARD}%"),
    ("Open pathways >52 weeks",               int((open_p["RTT_Weeks"] > 52).sum()), "Zero-tolerance"),
    ("Open pathways with no NHS Number",      int(open_p["No_NHS_Number"].sum()), "Cannot be traced"),
    ("Median waiting days (all)",             op["Waiting_Days"].median(),   ""),
    ("Mean waiting days (all)",               round(op["Waiting_Days"].mean(), 1), ""),
], columns=["Measure", "Value", "Note"], dtype=object)

dna_spec = (valid.pivot_table(index="Specialty_Code", columns="Attendance_Status",
                              values="Appointment_ID", aggfunc="count", fill_value=0)
                 .reindex(columns=VALID_STATUS, fill_value=0))
dna_spec["Total"] = dna_spec.sum(axis=1)
dna_spec["DNA_Rate_%"] = (dna_spec["DNA"] / dna_spec["Total"] * 100).round(1)
dna_spec["RAG"] = np.select([dna_spec["DNA_Rate_%"] > DNA_RED, dna_spec["DNA_Rate_%"] > DNA_TARGET],
                            ["Red", "Amber"], "Green")
dna_spec = dna_spec.sort_values("DNA_Rate_%", ascending=False).reset_index()
dna_spec.columns.name = None

bands = [18, 26, 40, 52, np.inf]
labels = ["18–26 wks", "26–40 wks", "40–52 wks", ">52 wks"]
rtt_list = breaches.assign(Breach_Band=pd.cut(breaches["RTT_Weeks"], bins=bands, labels=labels, right=True))
rtt_list = rtt_list[["Appointment_ID", "NHS_Number", "Specialty_Code", "Consultant_Code", "Appointment_Date",
                     "Attendance_Status", "RTT_Weeks", "Waiting_Days", "Breach_Band", "DQ_Flag"]] \
           .sort_values("RTT_Weeks", ascending=False).reset_index(drop=True)

print(rtt_list["Breach_Band"].value_counts().reindex(labels).to_string())
rtt_list.head(10)

def p92(s): return s.quantile(0.92)

wait_stats = (op.groupby("Specialty_Code")
                .agg(Appointments=("Appointment_ID", "count"),
                     Mean_Wait_Days=("Waiting_Days", "mean"),
                     Median_Wait_Days=("Waiting_Days", "median"),
                     P92_Wait_Days=("Waiting_Days", p92),
                     Max_Wait_Days=("Waiting_Days", "max"),
                     Open_Pathways=("Measurable_Open", "sum"))
                .round(1))
wait_stats["RTT_Breaches"] = breaches.groupby("Specialty_Code").size().reindex(wait_stats.index, fill_value=0)
wait_stats["RTT_Compliance_%"] = ((1 - wait_stats["RTT_Breaches"] / wait_stats["Open_Pathways"]) * 100).round(1)
wait_stats = wait_stats.sort_values("RTT_Breaches", ascending=False).reset_index()

def is_date(s, fmt="%d/%m/%Y"):  return pd.to_datetime(s, format=fmt, errors="coerce").notna()
def blank(s):                    return s.eq("")
def num(s):                      return pd.to_numeric(s, errors="coerce")
def dup(df, cols):               return df.duplicated(cols, keep="first")

RULES = {
 "Outpatients": lambda d: {
    ("Completeness", "NHS Number blank"):          blank(d.NHS_Number),
    ("Completeness", "RTT_Status / RTT_Weeks blank"): blank(d.RTT_Status) | blank(d.RTT_Weeks),
    ("Completeness", "Consultant blank"):          blank(d.Consultant_Code),
    ("Validity",     "Attendance status not standard"): ~d.Attendance_Status.isin(VALID_STATUS),
    ("Validity",     "Waiting_Days not a number >= 0"): ~(num(d.Waiting_Days) >= 0),
    ("Validity",     "Appointment time not HH:MM"): ~d.Appointment_Time.str.match(r"^\d{2}:\d{2}$"),
    ("Validity",     "Retired specialty code"):     d.Specialty_Code.isin(RETIRED_SPECIALTY),
    ("Validity",     "Referral source not standard"): ~d.Referral_Source.isin(["GP", "CONS", "ED", "SELF"]),
    ("Uniqueness",   "Duplicate Appointment_ID"):   dup(d, ["Appointment_ID"]),
 },
 "Inpatients": lambda d: {
    ("Completeness", "NHS Number blank"):          blank(d.NHS_Number),
    ("Completeness", "Discharge date blank (open episode)"): blank(d.Discharge_Date),
    ("Completeness", "Readmission flag blank"):    blank(d.Readmission_Flag),
    ("Completeness", "HRG code blank"):            blank(d.HRG_Code),
    ("Completeness", "Consultant / ICD10 / OPCS4 blank"): blank(d.Consultant_Code) | blank(d.ICD10_Code) | blank(d.OPCS4_Code),
    ("Validity",     "Admission type not standard"): ~d.Admission_Type.isin(["ELEC", "EMER", "TRANSFER"]),
    ("Validity",     "Discharge method not standard"): ~d.Discharge_Method.isin(["HOME", "TRANSFER", "DIED", "ABSENT", ""]),
    ("Validity",     "Discharge date unreadable"):  ~blank(d.Discharge_Date) & ~is_date(d.Discharge_Date),
    ("Validity",     "Retired specialty code"):     d.Specialty_Code.isin(RETIRED_SPECIALTY),
    ("Uniqueness",   "Duplicate Episode_ID"):       dup(d, ["Episode_ID"]),
    ("Consistency",  "Length of stay negative or != dates"): (num(d.Length_of_Stay) < 0) |
        (num(d.Length_of_Stay).notna() & is_date(d.Discharge_Date) &
         (num(d.Length_of_Stay) != (pd.to_datetime(d.Discharge_Date, format="%d/%m/%Y", errors="coerce")
                                    - pd.to_datetime(d.Admission_Date, format="%d/%m/%Y")).dt.days)),
 },
 "ED": lambda d: {
    ("Completeness", "NHS Number blank"):          blank(d.NHS_Number),
    ("Completeness", "Departure / clinician time blank"): blank(d.Departure_Time) | blank(d.Seen_by_Clinician_Time),
    ("Completeness", "Four-hour breach flag blank"): blank(d.Four_Hour_Breach),
    ("Validity",     "Triage category not 1–5"):    ~d.Triage_Category.isin(list("12345")),
    ("Validity",     "Arrival time not 24-hour HH:MM"): ~d.Arrival_Time.str.match(r"^\d{2}:\d{2}$"),
    ("Validity",     "Departure code not credible (DIED/LEFT)"): d.Departure_Code.isin(["DIED", "LEFT"]),
    ("Validity",     "Negative ED time"):           num(d.Total_ED_Time_Minutes) < 0,
    ("Uniqueness",   "Duplicate Attendance_ID"):    dup(d, ["Attendance_ID"]),
 },
 "Theatres": lambda d: {
    ("Completeness", "Cancellation counts blank"):  blank(d.Cancellations_Trust) | blank(d.Cancellations_Patient),
    ("Validity",     "Theatre ID not T1–T4"):        ~d.Theatre_ID.isin(["T1", "T2", "T3", "T4"]),
    ("Validity",     "Zero sessions available"):     num(d.Sessions_Available) == 0,
    ("Consistency",  "Sessions used > available"):   num(d.Sessions_Used) > num(d.Sessions_Available),
    ("Consistency",  "Utilisation_Pct != used/available"):
        ((num(d.Sessions_Used) / num(d.Sessions_Available) * 100).round(1) - num(d.Utilisation_Pct)).abs() > 0.15,
    ("Uniqueness",   "Duplicate week + theatre"):    dup(d, ["Week_Ending", "Theatre_ID"]),
 },
 "Workforce": lambda d: {
    ("Completeness", "Staff ID blank"):             blank(d.Staff_ID),
    ("Completeness", "Agency / absence flag blank"): blank(d.Agency_Flag) | blank(d.Absence_Flag),
    ("Validity",     "Test record (ST-99)"):        d.Staff_ID.str.startswith("ST-99"),
    ("Validity",     "Staff grade not standard"):   ~d.Staff_Grade.isin(["NURSE", "HCA", "REG", "SHO", "CONS"]),
    ("Validity",     "Shift type abbreviated"):     ~d.Shift_Type.isin(["DAY", "NIGHT", "LONG"]),
    ("Validity",     "Zero rostered hours"):        num(d.Hours_Rostered) == 0,
    ("Uniqueness",   "Duplicate Shift_ID"):         dup(d, ["Shift_ID"]),
 },
}

def score_dataset(name, df):
    checks = pd.DataFrame(RULES[name](df)).fillna(False).astype(bool)
    failed_any = checks.any(axis=1)
    score = (1 - failed_any.mean()) * 100
    detail = pd.DataFrame({"Dataset": name,
                           "Dimension": [c[0] for c in checks.columns],
                           "Check": [c[1] for c in checks.columns],
                           "Rows failing": checks.sum().values})
    dims = {dim: round((1 - checks.loc[:, [c for c in checks.columns if c[0] == dim]].any(axis=1).mean()) * 100, 1)
            for dim in ["Completeness", "Validity", "Uniqueness", "Consistency"]
            if any(c[0] == dim for c in checks.columns)}
    summary = {"Dataset": name, "Rows": len(df), "Rows failing ≥1 check": int(failed_any.sum()),
               "DQ Score %": round(score, 1), **{f"{k} %": v for k, v in dims.items()}}
    return summary, detail

results = [score_dataset(n, raw[n]) for n in FILES]
dq_scores = pd.DataFrame([r[0] for r in results])
dq_detail = pd.concat([r[1] for r in results], ignore_index=True)
dq_scores["RAG"] = np.select([dq_scores["DQ Score %"] >= DQ_GREEN, dq_scores["DQ Score %"] >= DQ_AMBER],
                             ["Green", "Amber"], "Red")
overall = (1 - dq_scores["Rows failing ≥1 check"].sum() / dq_scores["Rows"].sum()) * 100
print(f"Overall DQ Score across all five datasets: {overall:.1f}%")

dq_detail[dq_detail["Rows failing"] > 0].sort_values(["Dataset", "Rows failing"], ascending=[True, False])

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.formatting.rule import CellIsRule

NHS_BLUE, DARK_BLUE = "005EB8", "003087"
FILL = {"Green": "C6EFCE", "Amber": "FFEB9C", "Red": "FFC7CE"}
HDR_FONT, HDR_FILL = Font(name="Arial", bold=True, color="FFFFFF"), PatternFill("solid", fgColor=NHS_BLUE)
BODY, BOLD = Font(name="Arial", size=10), Font(name="Arial", size=10, bold=True)
THIN = Border(*(Side(style="thin", color="BFBFBF"),) * 4)

def write_table(ws, df, start_row, title=None, num_formats=None, widths=None):
    if title:
        ws.cell(start_row, 1, title).font = Font(name="Arial", bold=True, size=12, color=DARK_BLUE)
        start_row += 1
    for j, col in enumerate(df.columns, 1):
        c = ws.cell(start_row, j, str(col)); c.font, c.fill, c.border = HDR_FONT, HDR_FILL, THIN
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for i, row in enumerate(df.itertuples(index=False), start_row + 1):
        for j, val in enumerate(row, 1):
            if isinstance(val, pd.Timestamp): val = val.to_pydatetime()
            elif isinstance(val, (np.integer,)): val = int(val)
            elif isinstance(val, (np.floating,)): val = None if np.isnan(val) else float(val)
            c = ws.cell(i, j, val); c.font, c.border = BODY, THIN
            fmt = (num_formats or {}).get(df.columns[j - 1])
            if fmt: c.number_format = fmt
            if isinstance(val, datetime): c.number_format = "dd/mm/yyyy"
    for j, col in enumerate(df.columns, 1):
        w = (widths or {}).get(col) or min(max(len(str(col)), *(len(str(v)) for v in df.iloc[:, j-1].head(200)), 10) + 3, 45)
        ws.column_dimensions[get_column_letter(j)].width = w
    return start_row, start_row + len(df)          # header row, last data row

def rag_format(ws, rng):
    for k, v in FILL.items():
        ws.conditional_formatting.add(rng, CellIsRule(operator="equal", formula=[f'"{k}"'], fill=PatternFill("solid", fgColor=v)))

wb = Workbook()

# 1. Summary -------------------------------------------------------------------
ws = wb.active; ws.title = "Summary"
ws["A1"] = "Bronings University Hospital Group — Weekly Waiting List Exception Report"
ws["A1"].font = Font(name="Arial", bold=True, size=14, color=DARK_BLUE)
period = f"{op['Appointment_Date'].min():%d/%m/%Y} to {op['Appointment_Date'].max():%d/%m/%Y}"
ws["A2"] = f"Data period: {period}   ·   Generated automatically {RUN_TIME:%d/%m/%Y %H:%M}   ·   Source: PAS outpatient extract"
ws["A2"].font = Font(name="Arial", italic=True, size=9)
summary = pd.DataFrame([
    ("DNA rate",                f"{dna_rate:.1f}%",        f"< {DNA_TARGET:.0f}%",  "Red" if dna_rate > DNA_RED else "Amber" if dna_rate > DNA_TARGET else "Green"),
    ("RTT 18-week compliance",  f"{rtt_compliance:.2f}%",  f"{RTT_STANDARD:.0f}%",  "Green" if rtt_compliance >= RTT_STANDARD else "Amber" if rtt_compliance >= 80 else "Red"),
    ("RTT breaches (>18 weeks)", str(len(breaches)),            "0",                     "Red" if len(breaches) else "Green"),
    ("Open pathways >52 weeks", str(int((open_p['RTT_Weeks'] > 52).sum())), "0",          "Red" if (open_p['RTT_Weeks'] > 52).any() else "Green"),
    ("Median wait (days)",      f"{op['Waiting_Days'].median():.0f}", "—",            ""),
    ("Outpatient DQ Score",     f"{dq_scores.loc[dq_scores.Dataset=='Outpatients','DQ Score %'].iat[0]:.1f}%", f"≥ {DQ_GREEN:.0f}%",
                                dq_scores.loc[dq_scores.Dataset=='Outpatients','RAG'].iat[0]),
], columns=["Measure", "This week", "Target", "RAG"])
h, last = write_table(ws, summary, 4, widths={"Measure": 30, "This week": 14, "Target": 12, "RAG": 10})
rag_format(ws, f"D{h+1}:D{last}")

worst_dna = dna_spec.iloc[0]
worst_rtt = wait_stats.iloc[0]
no_nhs_breach = int(breaches["No_NHS_Number"].sum())
notes = [
    "Top exceptions this week",
    f"1. {len(breaches)} of {len(open_p)} open pathways have waited over 18 weeks; {int((open_p['RTT_Weeks']>52).sum())} exceed 52 weeks (longest {breaches['RTT_Weeks'].max():.1f} weeks).",
    f"2. {worst_rtt.Specialty_Code} has the most RTT breaches ({int(worst_rtt.RTT_Breaches)}).",
    f"3. {worst_dna.Specialty_Code} has the highest DNA rate ({worst_dna['DNA_Rate_%']:.1f}%) — {int(worst_dna.DNA)} DNAs.",
    f"4. {no_nhs_breach} breaching pathway(s) have no NHS Number and cannot be traced — correct at source this week.",
]
for i, t in enumerate(notes, last + 2):
    ws.cell(i, 1, t).font = BOLD if i == last + 2 else BODY
ws.freeze_panes = "A5"

# 2. RTT breaches --------------------------------------------------------------
ws = wb.create_sheet("RTT_Breaches")
h, last = write_table(ws, rtt_list.astype({"Breach_Band": str}), 1,
                      num_formats={"RTT_Weeks": "0.0", "Waiting_Days": "0"})
ws.freeze_panes = ws.cell(h + 1, 1); ws.auto_filter.ref = f"A{h}:{get_column_letter(rtt_list.shape[1])}{last}"
for r in range(h + 1, last + 1):
    if ws.cell(r, 7).value and ws.cell(r, 7).value > 52:
        for c in range(1, rtt_list.shape[1] + 1): ws.cell(r, c).fill = PatternFill("solid", fgColor=FILL["Red"])
    if ws.cell(r, 10).value:
        ws.cell(r, 10).fill = PatternFill("solid", fgColor=FILL["Amber"])

# 3. DNA by specialty ----------------------------------------------------------
ws = wb.create_sheet("DNA_by_Specialty")
h, last = write_table(ws, dna_spec, 1, title=f"DNA rate by specialty — DNA ÷ (ATT+DNA+CAN+REF); target {DNA_TARGET:.0f}%",
                      num_formats={"DNA_Rate_%": "0.0"})
rag_format(ws, f"H{h+1}:H{last}")
ws.cell(last + 1, 1, "Trust").font = BOLD
for j, col in enumerate(VALID_STATUS + ["Total"], 2):
    ws.cell(last + 1, j, f"=SUM({get_column_letter(j)}{h+1}:{get_column_letter(j)}{last})").font = BOLD
ws.cell(last + 1, 7, f"=ROUND(C{last+1}/F{last+1}*100,1)").font = BOLD     # live formula: 13.1

# 4. Waiting stats -------------------------------------------------------------
ws = wb.create_sheet("Waiting_Stats")
write_table(ws, wait_stats, 1, title="Waiting-time statistics by specialty (days) and RTT position",
            num_formats={c: "0.0" for c in wait_stats.columns if "Wait" in c or "%" in c})

# 5. DQ scores -----------------------------------------------------------------
ws = wb.create_sheet("DQ_Scores")
h, last = write_table(ws, dq_scores, 1, title="Data Quality Score by dataset — % of rows passing every check (DSP Toolkit)",
                      num_formats={c: "0.0" for c in dq_scores.columns if "%" in c})
rag_format(ws, f"{get_column_letter(dq_scores.columns.get_loc('RAG')+1)}{h+1}:{get_column_letter(dq_scores.columns.get_loc('RAG')+1)}{last}")
ws.cell(last + 1, 1, f"Overall: {overall:.1f}%   ·   RAG: Green ≥{DQ_GREEN:.0f}% · Amber {DQ_AMBER:.0f}–{DQ_GREEN-0.1:.1f}% · Red <{DQ_AMBER:.0f}%").font = BOLD
write_table(ws, dq_detail, last + 3, title="Check-level detail")

# 6. DQ exceptions (outpatients) -----------------------------------------------
ws = wb.create_sheet("DQ_Exceptions")
dq_exc = op.loc[op["DQ_Flag"].ne(""), ["Appointment_ID", "NHS_Number", "Specialty_Code", "Appointment_Date",
                                       "Attendance_Status_Raw", "RTT_Status", "RTT_Weeks", "DQ_Flag"]]
h, last = write_table(ws, dq_exc, 1, title="Outpatient records to correct at source (PAS)")
ws.auto_filter.ref = f"A{h}:H{last}"

# 7. Audit log -----------------------------------------------------------------
ws = wb.create_sheet("Audit_Log")
audit = pd.DataFrame({"Item": ["Run time", "Run by", "Notebook", "Rows read (outpatients)",
                               "Rows with valid status", "Measurable open pathways"] + [f"Input: {k}" for k in FILES],
                      "Value": [f"{RUN_TIME:%d/%m/%Y %H:%M:%S}", "Automated (Python 3 / pandas)", "Waiting_List_Exception_Report.ipynb",
                                len(op_raw), len(valid), len(open_p)] + [f"{FILES[k]} ({len(raw[k])} rows)" for k in FILES]})
h, last = write_table(ws, audit, 1, title="Audit log", widths={"Item": 32, "Value": 60})
write_table(ws, clean_log, last + 3, title="Cleaning rules applied", widths={"Action": 60})

out_file = OUTPUT_DIR / f"Waiting_List_Exception_Report_{RUN_TIME:%Y-%m-%d}.xlsx"
wb.save(out_file)
print(f"Saved {out_file}  ·  sheets: {', '.join(wb.sheetnames)}")
print(f"Total run time: {(datetime.now() - RUN_TIME).total_seconds():.1f} seconds")

