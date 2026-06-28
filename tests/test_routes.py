import os
import tempfile
import unittest

os.environ.setdefault("DATA_DIR", tempfile.mkdtemp())

from fastapi.testclient import TestClient

from app import main


class FakeManager:
    def get_account(self, acc_id):
        return {"id": acc_id, "symbol": "XAUUSDc"}

    def get_account_data(self, acc_id):
        return {
            "XAUUSDc": {"symbol": "XAUUSDc", "bid": 4063.1, "ask": 4063.3},
            "bars_1m": {
                "symbol": "XAUUSDc",
                "bars": [{"Date": "2026.06.29 01:00:00", "Open": 1, "High": 2, "Low": 1, "Close": 2, "Volume": 3}],
            },
        }


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.old_manager = main.manager
        main.manager = FakeManager()
        self.client = TestClient(main.app)

    def tearDown(self):
        main.manager = self.old_manager

    def test_price_keeps_broker_symbol_case(self):
        res = self.client.get("/api/accounts/1/price")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["symbol"], "XAUUSDc")

    def test_price_accepts_wrong_case_without_breaking_symbol(self):
        res = self.client.get("/api/accounts/1/price?symbol=XAUUSDC")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["symbol"], "XAUUSDc")

    def test_bars_timeframe_route_uses_account_symbol(self):
        res = self.client.get("/api/accounts/1/bars/1m?count=1")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["symbol"], "XAUUSDc")


if __name__ == "__main__":
    unittest.main()
