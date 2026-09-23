import importlib.util
import json
import pathlib
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
        self.assertEqual(result["plugins"], [{"id": "keep", "custom": [1, 2]}, {"id": "kevinbsr.omahub", "integrations": {"omaconnect": {"showBattery": True}}}])
        self.assertEqual(result["disabledPlugins"], ["omaconnect", "keep-disabled"])
        self.assertEqual(result["idle"], config["idle"])
        self.assertEqual(len(config["bar"]["layout"]["right"]), 1)
        self.assertEqual(integration.service_config(result, "omaconnect"), result)

    def test_deduplicates_service_and_preserves_service_preferences(self):
        config = {"plugins": [{"id": "agx.screen-time", "option": 1}, "agx.screen-time"],
                  "bar": {"layout": {"center": [{"id": "agx.screen-time", "option": 0, "custom": True}]}}}
        result = integration.service_config(config, "agx.screen-time")
        self.assertEqual(result["plugins"], [{"id": "kevinbsr.omahub", "integrations": {"agx.screen-time": {"option": 1, "custom": True}}}])
        self.assertFalse(result["bar"]["layout"]["center"])

    def test_rejects_unrelated_plugin(self):
        with self.assertRaises(ValueError):
            integration.service_config({}, "unrelated")

    def test_minimal_config(self):
        self.assertEqual(integration.service_config({}, "omaconnect"), {"plugins": [{"id": "kevinbsr.omahub", "integrations": {"omaconnect": {}}}], "disabledPlugins": ["omaconnect"]})

    def test_migrates_all_without_losing_hub_or_receiver_preferences(self):
        config = {"bar": {"layout": {"right": [{"id": "kevinbsr.omahub", "birthYear": 2000}]}},
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
        config = {"bar": {"layout": {"center": ["kevinbsr.omahub", "other"]}}}
        result = integration.service_config(config, "omaconnect")
        self.assertEqual(result["bar"]["layout"]["center"],
                         [{"id": "kevinbsr.omahub", "integrations": {"omaconnect": {}}}, "other"])


class VendoredTests(unittest.TestCase):
    def test_vendored_engines_need_no_install(self):
        for plugin in ("agx.screen-time", "omaconnect", "io.github.ayan-de.android-mirror"):
            self.assertTrue(integration.vendored(plugin), plugin)

    def test_nearby_is_not_vendored(self):
        # Its versioned helper binary belongs with its own plugin, so Nearby is
        # hosted only when that plugin is installed.
        self.assertNotIn("oma.nearby", integration.VENDORED)
        self.assertFalse(integration.vendored("oma.nearby"))

    def test_every_vendored_engine_is_an_allowed_integration(self):
        self.assertTrue(integration.VENDORED <= integration.ALLOWED)

    def test_vendored_engines_have_a_pinned_tree(self):
        vendor = pathlib.Path(__file__).parents[1] / "vendor"
        pinned = {e["name"] for e in json.loads((vendor / "vendor.json").read_text())["engines"]}
        for name in pinned:
            self.assertTrue((vendor / name).is_dir(), name)


if __name__ == "__main__":
    unittest.main()
