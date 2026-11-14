"""Check traffic boundaries, gaps, collector resets and concurrent SQLite reads."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / 'config/yokai/scripts'
if len(sys.argv) > 2 and sys.argv[1] == '--scripts':
    SCRIPTS = Path(sys.argv[2])
    del sys.argv[1:3]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('network_history', SCRIPTS / 'network_history.py')
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)


class NetworkHistoryChecks(unittest.TestCase):
    def test_elapsed_reset_new_interface_and_suspend(self):
        sampler = history.Sampler()
        rows, backwards = sampler.sample({'wifi': (1, 100, 200)}, 1000, 100)
        self.assertEqual(rows, [('wifi', 1000, 1000, 0, None, None)])
        rows, _ = sampler.sample({'wifi': (1, 500, 400), 'vpn': (2, 9000, 1000)}, 1004, 104)
        self.assertEqual(rows[0], ('wifi', 1000, 1004, 4, 400, 200))
        self.assertEqual(rows[1][-2:], (None, None))
        rows, _ = sampler.sample({'wifi': (1, 10, 600)}, 1009, 109)
        self.assertEqual(rows[0][-2:], (None, 200))
        # Wall time advances through suspension; monotonic time does not.
        rows, _ = sampler.sample({'wifi': (1, 99999, 99999)}, 1609, 114)
        self.assertEqual(rows[0][-3:], (0, None, None))
        rows, backwards = sampler.sample({'wifi': (1, 100000, 100000)}, 1500, 119)
        self.assertTrue(backwards)
        self.assertEqual(rows[0][-3:], (0, None, None))
        rows, _ = sampler.sample({'wifi': (1, 200000, 200000)}, 1530, 149)
        self.assertEqual(rows[0][-3:], (0, None, None))
        # A replacement interface may start with counters larger than the old one's.
        rows, _ = sampler.sample({'wifi': (3, 300000, 300000)}, 1535, 154)
        self.assertEqual(rows[0][-3:], (0, None, None))

    def test_period_boundaries_and_explicit_gaps(self):
        # Window [100, 1000]. The first interval crosses its left boundary.
        rows = [(95, 105, 10, 1000, 2000), (105, 110, 5, 500, None),
                (115, 120, 5, 1000, 500), (995, 1000, 5, 250, 50)]
        data = history.summarize('wifi', 900, 1000, rows, 95)
        self.assertEqual(data['totals'], {'download': 2250, 'upload': 1550})
        self.assertEqual(data['latest'], {'download': 50, 'upload': 10})
        self.assertEqual(data['points'][0]['download'], 100)
        self.assertEqual(data['points'][0]['upload'], 200)
        self.assertEqual(data['points'][1]['download'], 100)
        self.assertIsNone(data['points'][1]['upload'])
        self.assertIsNone(data['points'][2]['download'])
        self.assertEqual(data['points'][3]['download'], 200)
        self.assertEqual(data['points'][-1]['download'], 50)
        stale = history.summarize('wifi', 900, 1020, rows, 95)
        self.assertEqual(stale['latest'], {'download': None, 'upload': None})

    def test_short_gap_is_not_hidden_in_large_bins(self):
        data = history.summarize('wifi', 86400, 86400,
                                 [(0, 200, 200, 20000, 0), (205, 480, 275, 27500, 0)], 0)
        self.assertIsNone(data['points'][0]['download'])
        self.assertEqual(data['totals']['download'], 47500)

    def test_fresh_coarse_history_uses_only_actual_observed_span(self):
        data = history.summarize('wifi', 86400, 86400, [(86385, 86395, 10, 1000, 500)], 86385)
        valid = [point for point in data['points'] if point['download'] is not None]
        self.assertEqual(valid, [{'time': 86390, 'download': 100, 'upload': 50}])
        self.assertLessEqual(len(data['points']), 184)
        index = data['points'].index(valid[0])
        self.assertIsNone(data['points'][index - 1]['download'])
        self.assertIsNone(data['points'][index + 1]['download'])
        self.assertGreater(data['points'][index - 1]['time'], 85920)
        self.assertEqual(data['totals'], {'download': 1000, 'upload': 500})

    def test_disjoint_directional_observations_keep_their_real_timestamps(self):
        data = history.summarize('wifi', 86400, 86400,
                                 [(86000, 86005, 5, 1000, None),
                                  (86200, 86205, 5, None, 500)], 86000)
        download = [point for point in data['points'] if point['download'] is not None]
        upload = [point for point in data['points'] if point['upload'] is not None]
        self.assertEqual(download, [{'time': 86002.5, 'download': 200, 'upload': None}])
        self.assertEqual(upload, [{'time': 86202.5, 'download': None, 'upload': 100}])
        self.assertLessEqual(len(data['points']), 188)

    def test_directional_gap_does_not_interrupt_the_other_series(self):
        rows = [(start, start + 5, 5, 500, 50 if start >= 86200 else None)
                for start in range(85440, 86400, 5)]
        data = history.summarize('wifi', 86400, 86400, rows, 85440)
        upload_start = next(point for point in data['points'] if point.get('gap') == 'upload')
        self.assertAlmostEqual(upload_start['time'], 86200, places=5)
        download = [point for point in data['points'] if point.get('gap', 'download') == 'download'
                    and 85680 <= point['time'] <= 86300]
        self.assertEqual([point['download'] for point in download], [100, 100])
        self.assertEqual(data['totals'], {'download': 96000, 'upload': 2000})

    def test_retention_restart_read_only_and_concurrent_reader(self):
        with tempfile.TemporaryDirectory(prefix='yokai-history-check-') as directory:
            path = Path(directory) / 'network.sqlite3'
            missing = history.read_history(path, 'wifi', 900, now=90000)
            self.assertFalse(path.exists(), 'Reading absent history must not create a database')
            self.assertIsNone(missing['observedSince'])
            self.assertTrue(all(point['download'] is None for point in missing['points']))
            writer = history.open_writer(path)
            try:
                history.write_sample(writer, [('wifi', 0, 5, 5, 100, 100),
                                              ('wifi', 89995, 90000, 5, 500, 100)], 90000, prune=True)
                self.assertEqual(writer.execute('SELECT COUNT(*) FROM intervals').fetchone()[0], 1)
                data = history.read_history(path, 'wifi', 900, now=90000)
                self.assertEqual(data['totals'], {'download': 500, 'upload': 100})
                # An uncommitted collector write cannot block or leak into a reader.
                writer.execute('INSERT INTO intervals(interface,start,end,elapsed,download,upload) '
                               'VALUES (?, ?, ?, ?, ?, ?)', ('wifi', 90000, 90005, 5, 2000, 0))
                concurrent = history.read_history(path, 'wifi', 900, now=90005)
                self.assertEqual(concurrent['totals']['download'], 500)
                writer.commit()
                self.assertEqual(history.read_history(path, 'wifi', 900, now=90005)['totals']['download'], 2500)
                # A fresh process establishes a null baseline instead of counting the outage.
                rows, _ = history.Sampler().sample({'wifi': (1, 100000, 200000)}, 90010, 100)
                history.write_sample(writer, rows, 90010)
                self.assertEqual(history.read_history(path, 'wifi', 900, now=90010)['latest'],
                                 {'download': None, 'upload': None})
                history.write_sample(writer, [('wifi', 89990, 89990, 0, None, None)],
                                     89990, backwards=True)
                self.assertEqual(writer.execute('SELECT MAX(end) FROM intervals').fetchone()[0], 89990)
            finally:
                writer.close()
            path.write_bytes(b'not a database')
            self.assertIn('error', history.read_history(path, 'wifi', 900, now=90000))


if __name__ == '__main__':
    unittest.main()
