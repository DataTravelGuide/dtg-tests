import subprocess

from avocado import Test


class TeafsTest(Test):
    def setUp(self):
        """Collect parameters for the teafs script"""
        self.env_dict = {}
        for path, key, value in self.params.iteritems():
            self.env_dict[key] = value
        self.log.info("env_dict: %s", self.env_dict)

    def run_teafs_script(self):
        env_vars = ' '.join([f'{key}="{value}"' for key, value in self.env_dict.items()])
        cmd = f"pwd;{env_vars} {self.params.get('test_script')}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        print(result.stdout)
        print(result.stderr)

        if result.returncode == 0:
            self.log.info("teafs script completed successfully")
        else:
            self.fail(result)

    def test(self):
        self.run_teafs_script()

    def tearDown(self):
        self.log.info("teafs test finished.")
