import os
import subprocess
import json

from avocado import Test
from avocado.utils import process


class CbdctrlTest(Test):

    def setUp(self):
        """
        In the setup phase, get all parameters and construct the command
        """
        self.env_dict = {}
        # Iterate over all parameters and store them in env_dict
        for path, key, value in self.params.iteritems():
            self.env_dict[key] = value

        self.log.info("env_dict: %s\n", self.env_dict)

    def run_cbdctrl_script(self):
        """
        Execute the cbdctrl.sh script with environment variables set from env_dict
        """
        # Cbdctrl the environment variable string
        env_vars = ' '.join([f'{key}="{value}"' for key, value in self.env_dict.items()])

        # Add environment variables to the cbdctrl command
        cbdctrl_command = f"pwd;{env_vars} ./cbdctrl.py.data/cbdctrl.sh"

        # Execute the command and capture the output
        result = subprocess.run(
            cbdctrl_command,
            shell=True,  # Use shell to execute the command
            capture_output=True,  # Capture both stdout and stderr
            text=True  # Return output as a string
        )

        # Output the result of the command execution
        if result.returncode == 0:
            print("Cbdctrl completed successfully:")
            print(result.stdout)  # Print standard output
        else:
            print("Cbdctrl failed with error:")
            print(result.stdout)  # Print standard error
            print(result.stderr)  # Print standard error
            self.fail(result)

    def test(self):
        """
        Execute the cbdctrl.sh script as part of the test case
        """
        result = self.run_cbdctrl_script()  # Run the cbdctrl.sh script

    def tearDown(self):
        """
        Tear down and log completion of the cbdctrl test
        """
        self.log.info("Cbdctrl test finished.")
