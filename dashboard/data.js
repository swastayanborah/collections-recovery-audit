window.DASH = {
 "audit": [
  {
   "step": 1,
   "label": "Reported (raw SUCCESS rows, Feb -> Mar)",
   "value_pct": 10.991610813832331,
   "change_from_previous": null
  },
  {
   "step": 2,
   "label": "After removing duplicate payment rows",
   "value_pct": 11.031885249801876,
   "change_from_previous": 0.04027443596954505
  },
  {
   "step": 3,
   "label": "After adjusting for days in month (28 vs 31)",
   "value_pct": 0.2868640965952629,
   "change_from_previous": -10.745021153206613
  }
 ],
 "monthly": [
  {
   "m": "Jan",
   "reported_cr": 19.113328441999982,
   "true_cr_30d": 18.11894783129033
  },
  {
   "m": "Feb",
   "reported_cr": 17.409728795999975,
   "true_cr_30d": 18.22954861714286
  },
  {
   "m": "Mar",
   "reported_cr": 19.32333842899999,
   "true_cr_30d": 18.28184264709682
  },
  {
   "m": "Apr",
   "reported_cr": 17.84270170499993,
   "true_cr_30d": 17.51380434099996
  },
  {
   "m": "May",
   "reported_cr": 18.70481443400005,
   "true_cr_30d": 17.83067211290323
  },
  {
   "m": "Jun",
   "reported_cr": 17.87244934599998,
   "true_cr_30d": 17.55597269699997
  },
  {
   "m": "Jul",
   "reported_cr": 19.027884688000018,
   "true_cr_30d": 18.12021920129034
  }
 ],
 "kpi": {
  "lakh_per_day": 59.833813070344526,
  "trend_pct": -0.3554416908750307,
  "kept_true": 24.783905831996268,
  "kept_naive": 49.367187207125795,
  "paise_per_rupee": 0.7172232263898933
 },
 "payments": {
  "raw_cr": 191.7258617149993,
  "golden_cr": 131.55839646399957
 },
 "attr7": 9.165050758526291,
 "suspects": [
  {
   "code": "A",
   "suspect": "Duplicate payments",
   "evidence": "FACT",
   "finding": "500 duplicate rows (Rs 3.84 Cr); Rs 57.6 Cr of FAILED/PENDING/REVERSED rows sit in the same table"
  },
  {
   "code": "B",
   "suspect": "Attribution errors",
   "evidence": "FACT",
   "finding": "Last-touch credits 67% of payments to a channel; only 9% had a touch in the 7 days before paying"
  },
  {
   "code": "C",
   "suspect": "Timezone problems",
   "evidence": "FACT",
   "finding": "67% of calls are stored in UTC or Dubai time; converting to IST moves 67% of all calls to a different hour"
  },
  {
   "code": "D",
   "suspect": "Disposition code changes",
   "evidence": "FACT",
   "finding": "3 code versions run side by side all year; PTP is logged as both PTP and PROMISE_TO_PAY, so counting one code halves PTPs"
  },
  {
   "code": "E",
   "suspect": "Agent identity",
   "evidence": "FACT",
   "finding": "30000 agent rows -> 1000 real agents; 1099 employee codes, 1099 of them shared across agents"
  },
  {
   "code": "F",
   "suspect": "Portfolio mix change",
   "evidence": "STRONG",
   "finding": "Largest monthly swing in any segment share of collections: 3.9 pts -> no meaningful mix shift"
  },
  {
   "code": "G",
   "suspect": "Denominator manipulation",
   "evidence": "STRONG",
   "finding": "Rate on worked accounts only is 1.0x the rate on the full book"
  }
 ]
};
