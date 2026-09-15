import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("integration", Path(__file__).parents[1] / "scripts/integration_service.py")
integration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(integration)


class ServiceConfigTests(unittest.TestCase):
    def test_moves_only_requested_widget_and_preserves_settings(self):
        config = {
            "bar": {"layout": {"left": [{"id": "other", "x": 7}], "right": [{"id": "omaconnect", "showBattery": True}]}},
            "plugins": [{"id": "keep", "custom": [1, 2]}],
            "disabledPlugins": ["omaconnect", "keep-disabled"],
            "idle": {"lock": 600},
        }
        result = integration.service_config(config, "omaconnect")
        self.assertEqual(result["bar"]["layout"]["right"], [])
        self.assertEqual(result["bar"]["layout"]["left"], config["bar"]["layout"]["left"])
        self.assertEqual(result["plugins"], [{"id": "keep", "custom": [1, 2]}, {"id": "kevin.hub", "integrations": {"omaconnect": {"showBattery": True}}}])
        self.assertEqual(result["disabledPlugins"], ["omaconnect", "keep-disabled"])
        self.assertEqual(result["idle"], config["idle"])
        self.assertEqual(len(config["bar"]["layout"]["right"]), 1)
        self.assertEqual(integration.service_config(result, "omaconnect"), result)

    def test_deduplicates_service_and_preserves_service_preferences(self):
        config = {"plugins": [{"id": "agx.screen-time", "option": 1}, "agx.screen-time"],
                  "bar": {"layout": {"center": [{"id": "agx.screen-time", "option": 0, "custom": True}]}}}
        result = integration.service_config(config, "agx.screen-time")
        self.assertEqual(result["plugins"], [{"id": "kevin.hub", "integrations": {"agx.screen-time": {"option": 1, "custom": True}}}])
        self.assertFalse(result["bar"]["layout"]["center"])

    def test_rejects_unrelated_plugin(self):
        with self.assertRaises(ValueError):
            integration.service_config({}, "unrelated")

    def test_minimal_config(self):
        self.assertEqual(integration.service_config({}, "omaconnect"), {"plugins": [{"id": "kevin.hub", "integrations": {"omaconnect": {}}}], "disabledPlugins": ["omaconnect"]})

    def test_migrates_all_without_losing_hub_or_receiver_preferences(self):
        config = {"bar": {"layout": {"right": [{"id": "kevin.hub", "birthYear": 2000}]}},
                  "plugins": [{"id": "oma.nearby", "receiverEnabled": False},
                              {"id": "omaconnect"}, {"id": "agx.screen-time"}]}
        for plugin in sorted(integration.ALLOWED):
            config = integration.service_config(config, plugin)
        hub = config["bar"]["layout"]["right"][0]
        self.assertEqual(hub["birthYear"], 2000)
        self.assertFalse(hub["integrations"]["oma.nearby"]["receiverEnabled"])
        self.assertEqual(set(hub["integrations"]), integration.ALLOWED)
        self.assertEqual(config["plugins"], [])
        self.assertEqual(set(config["disabledPlugins"]), integration.ALLOWED)
        self.assertEqual(integration.service_config(config, "oma.nearby"), config)

    def test_promotes_string_hub_without_moving_it(self):
        config = {"bar": {"layout": {"center": ["kevin.hub", "other"]}}}
        result = integration.service_config(config, "omaconnect")
        self.assertEqual(result["bar"]["layout"]["center"],
                         [{"id": "kevin.hub", "integrations": {"omaconnect": {}}}, "other"])


if __name__ == "__main__":
    unittest.main()
