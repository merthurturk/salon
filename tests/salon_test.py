# Run with: python3 -I tests/salon_test.py
import json, os, subprocess, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = {"artists": {"goya": {"name": "Francisco Goya"}}, "paintings": [
    {"key": "goya-dog-1823", "artist": "goya", "title": "The Dog", "year": "1823", "image": "http://not-allowed.example/x.jpg"},
    {"key": "goya-saturn-1823", "artist": "goya", "title": "Saturn", "year": "1823", "image": "http://not-allowed.example/y.jpg"},
]}


class Salon(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        with open(os.path.join(self.dir, "catalog.json"), "w") as f:
            json.dump(CATALOG, f)
        self.env = dict(os.environ, SALON_STATE=os.path.join(self.dir, "state"),
                        SALON_CATALOG=os.path.join(self.dir, "catalog.json"),
                        SALON_CE=os.path.join(ROOT, "tests", "fake-ce"),
                        FAKE_CE_DB=os.path.join(self.dir, "ce.json"))

    def run_salon(self, *args, down=False, state=None):
        env = dict(self.env, **({"FAKE_CE_DOWN": "1"} if down else {}))
        if state:
            env["SALON_STATE"] = os.path.join(self.dir, state)
        r = subprocess.run([os.path.join(ROOT, "bin", "salon"), *args], env=env, capture_output=True, text=True)
        return r.returncode, json.loads(r.stdout.splitlines()[-1]) if r.stdout.strip() else None

    def favorites(self, state="state"):
        with open(os.path.join(self.dir, state, "favorites.json")) as f:
            return json.load(f)["items"]

    def notes(self):
        with open(self.env["FAKE_CE_DB"]) as f:
            return json.load(f)

    def test_add_reaches_context_engine(self):
        code, result = self.run_salon("fav", "add", "goya-dog-1823")
        self.assertEqual((code, result["synced"]), (0, True))
        self.assertEqual(self.favorites()["goya-dog-1823"]["pending"], "")
        note = self.notes()["note::salon-favourite-goya-dog-1823"]
        self.assertIn("salon-favourite", note["tags"])
        self.assertEqual(note["title"], "Favourite painting: The Dog — Francisco Goya, 1823")

    def test_remove_archives_the_note(self):
        self.run_salon("fav", "add", "goya-dog-1823")
        self.run_salon("fav", "remove", "goya-dog-1823")
        self.assertNotIn("goya-dog-1823", self.favorites())
        self.assertTrue(self.notes()["note::salon-favourite-goya-dog-1823"]["archived"])

    def test_offline_changes_wait_for_the_next_sync(self):
        code, result = self.run_salon("fav", "add", "goya-dog-1823", down=True)
        self.assertEqual((code, result["synced"]), (0, False))
        self.assertEqual(self.favorites()["goya-dog-1823"]["pending"], "add")
        self.run_salon("sync")
        self.assertEqual(self.favorites()["goya-dog-1823"]["pending"], "")
        self.assertIn("note::salon-favourite-goya-dog-1823", self.notes())

    def test_offline_sync_removes_nothing(self):
        self.run_salon("fav", "add", "goya-dog-1823")
        self.run_salon("sync", down=True)
        self.assertIn("goya-dog-1823", self.favorites())

    def test_favourites_from_another_machine_arrive(self):
        self.run_salon("fav", "add", "goya-saturn-1823", state="other")
        self.run_salon("sync")
        self.assertIn("goya-saturn-1823", self.favorites())
        # …and a removal there reaches this machine too.
        self.run_salon("fav", "remove", "goya-saturn-1823", state="other")
        self.run_salon("sync")
        self.assertNotIn("goya-saturn-1823", self.favorites())

    def test_readding_restores_an_archived_note(self):
        self.run_salon("fav", "add", "goya-dog-1823")
        self.run_salon("fav", "remove", "goya-dog-1823")
        self.run_salon("fav", "add", "goya-dog-1823")
        self.assertFalse(self.notes()["note::salon-favourite-goya-dog-1823"]["archived"])

    def test_unknown_painting_is_refused(self):
        code, _ = self.run_salon("fav", "add", "nobody-nothing")
        self.assertEqual(code, 1)

    def test_images_only_from_known_hosts(self):
        self.run_salon("fav", "add", "goya-dog-1823")
        self.assertEqual(self.favorites()["goya-dog-1823"]["cached"], "")


if __name__ == "__main__":
    unittest.main()
