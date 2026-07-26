from __future__ import annotations

import unittest

from pipeline.__main__ import classify_dashboard_json_diff


class ContactDistributionDiffWhitelistTests(unittest.TestCase):
    """The contact ring deliberately did not widen the frozen diff gate.

    The release plan assumed the parity export diff would block on the new
    top-level contact_distribution key. It does not: release-league writes the
    parity exports straight from the promoted bundle and treats any bundle diff
    as fatal, without consulting this classifier. The classifier is reached
    only by the per-team `release` command and by `diff-dashboard-json`.

    Adding a whitelist entry would therefore have pre-authorised a whole new
    payload section on two paths that do not need it, for no benefit on the
    path actually used. If either path ever meets the section, blocking is the
    correct outcome and it belongs in a recorded adjudication.

    These tests pin that decision so it is not quietly reversed.
    """

    def test_contact_distribution_is_not_whitelisted(self) -> None:
        for kind in ("extra_in_new", "missing_in_new", "value_mismatch"):
            with self.subTest(kind=kind):
                self.assertIsNone(
                    classify_dashboard_json_diff("contact_distribution", kind)
                )

    def test_values_inside_the_section_are_not_whitelisted(self) -> None:
        for path in (
            "contact_distribution.length",
            "contact_distribution[0]",
            "contact_distribution[0].time_loss_injuries",
        ):
            with self.subTest(path=path):
                self.assertIsNone(classify_dashboard_json_diff(path, "value_mismatch"))

    def test_the_established_whitelist_still_works(self) -> None:
        """Guard against over-correcting and gutting the real entries."""
        self.assertIsNotNone(classify_dashboard_json_diff("generated_at", "value_mismatch"))
        self.assertIsNotNone(
            classify_dashboard_json_diff("coverage.scope_status_counts", "extra_in_new")
        )


if __name__ == "__main__":
    unittest.main()
