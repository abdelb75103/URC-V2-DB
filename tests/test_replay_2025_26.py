from __future__ import annotations
import hashlib, importlib.util, json, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("year2_replay", ROOT / "tools/replay_2025_26.py")
assert SPEC and SPEC.loader
R = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(R)
HEADERS = ["Team", "PlayerID", "Received At Club", "Received/Injured In Team", "Problem type", "Date Injured", "Fit For Selection Date", "Confirmed Return Date", "Days Injured", "Occasion category", "Body Part", "Orchard Code", "Illness Code", "Description", "Injury Tissue Type/s", "Side", "Nature of onset", "Recurrence", "Is Contact", "Mechanism of Injury", "Mechanism Notes", "Injury Surface Type", "Match Type", "Received At Position", "Required Surgery", "TimeLoss vs Medical Attention", "Diagnosis", "Exclusion Reason"]

class Year2ReplayTests(unittest.TestCase):
 def payload(self): return {"format":"urc-master-workbook","sheets":[{"name":"Injury Master","values":[HEADERS,["A","P1"]+ [""]*26]}]}
 def ledger(self, master): return {"season":"2025-26","reporting_window":R.WINDOW,"baseline":{"master":{"sha256":hashlib.sha256(master.read_bytes()).hexdigest()}},"steps":[]}
 def test_replays_deterministically_and_generates_methodology(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d); master=p/'master.json'; master.write_text(json.dumps(self.payload())); ledger=p/'ledger.json'; ledger.write_text(json.dumps(self.ledger(master))); out=p/'included.csv'; manifest=p/'manifest.json'; methodology=p/'method.md'
   result=R.replay(master,ledger,out,manifest,methodology)
   self.assertEqual(result['season'],'2025-26'); self.assertEqual(result['columns'],28); self.assertIn('September 2025',methodology.read_text())
 def test_rejects_year1_evidence_without_writing_output(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d); master=p/'master.json'; master.write_text(json.dumps(self.payload())); ledger=self.ledger(master); ledger['steps']=[{"season":"2025-26","entries":[{"season":"2025-26","evidence_locator":"evidence/2024-25/x"}]}]; lp=p/'ledger.json'; lp.write_text(json.dumps(ledger)); out=p/'out.csv'
   with self.assertRaisesRegex(R.Year2ReplayError,'evidence locator'): R.replay(master,lp,out,p/'m.json',p/'method.md')
   self.assertFalse(out.exists())
