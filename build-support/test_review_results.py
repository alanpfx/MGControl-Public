import importlib.util,json,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('review_results',Path(__file__).with_name('review-results.py'))
review=importlib.util.module_from_spec(spec);spec.loader.exec_module(review)

def fixture(unit=8,ui=2):
    return ("Private implementation detail and synthetic-marker\n"
            f"Test Suite 'MGControlTests.xctest' passed at 2026-11-07\n Executed {unit} tests, with 0 failures (0 unexpected)\n"
            f"Test Suite 'MGControlUITests.xctest' passed at 2026-11-07\n Executed {ui} tests, with 0 failures (0 unexpected)\n** TEST SUCCEEDED **")

class ReviewResultsTests(unittest.TestCase):
    def test_totals_do_not_export_source_or_diagnostics(self):
        value=review.test_totals(fixture());self.assertEqual(value,{'unit':{'tests':8,'failures':0},'ui':{'tests':2,'failures':0}})
        self.assertNotIn('synthetic-marker',json.dumps(value));self.assertNotIn('Private implementation',json.dumps(value))
    def test_failed_missing_and_empty_suites_never_claim_success(self):
        for log in [fixture().replace('** TEST SUCCEEDED **',''),fixture().replace('MGControlUITests.xctest','Other'),fixture(0,2),fixture(8,0),fixture().replace('0 failures','1 failures')]:
            with self.assertRaises(ValueError):review.test_totals(log)
    def test_metadata_is_sourced_from_version_file_and_cannot_inject_environment(self):
        self.assertEqual(review.version_metadata({'marketingVersion':'1.2','buildNumber':3}),{'version':'1.2','build':3})
        for value in [{'marketingVersion':'1.2\nX=1','buildNumber':3},{'marketingVersion':'1.2','buildNumber':True},{'marketingVersion':'1.2','buildNumber':0}]:
            with self.assertRaises(ValueError):review.version_metadata(value)

if __name__=='__main__':unittest.main()
