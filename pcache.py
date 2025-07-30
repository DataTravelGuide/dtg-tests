import os
import subprocess

from avocado import Test

class PcacheTest(Test):
    def setUp(self):
        """Collect parameters for the pcache script"""
        self.env_dict = {}
        for path, key, value in self.params.iteritems():
            self.env_dict[key] = value
        self.striped = str(self.params.get('striped', default='false')).lower()
        self.env_dict['striped'] = self.striped
        self.log.info("env_dict: %s", self.env_dict)

    def run_pcache_script(self):
        env_vars = ' '.join([f'{key}="{value}"' for key, value in self.env_dict.items()])
        cmd = f"pwd;{env_vars} {self.params.get('test_script')}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        print(result.stdout)

        if result.returncode == 0:
            self.log.info("pcache script completed successfully")
        else:
            self.log.error("pcache script failed: %s", result.stderr)
            self.fail(result)

    def test(self):
        self.run_pcache_script()

    def tearDown(self):
        self.log.info("pcache test finished.")
