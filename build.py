import os
import subprocess
import json

from avocado import Test
from avocado.utils import process


class BuildTest(Test):

    def setUp(self):
        """
        In the setup phase, get all parameters and construct the command
        """
        self.env_dict = {}
        # Iterate over all parameters and store them in env_dict
        for path, key, value in self.params.iteritems():
            self.env_dict[key] = value

        self.log.info("env_dict: %s\n", self.env_dict)

    def run_build_script(self):
        """
        Execute the build.sh script with environment variables set from env_dict
        """
        # Build the environment variable string
        env_vars = ' '.join([f'{key}="{value}"' for key, value in self.env_dict.items()])

        # Add environment variables to the build command
        build_command = f"pwd;{env_vars} ./build.py.data/build.sh"

        # Execute the command and capture the output
        result = subprocess.run(
            build_command,
            shell=True,  # Use shell to execute the command
            capture_output=True,  # Capture both stdout and stderr
            text=True  # Return output as a string
        )

        # Output the result of the command execution
        if result.returncode == 0:
            print("Build completed successfully:")
            print(result.stdout)  # Print standard output
        else:
            print("Build failed with error:")
            print(result.stderr)  # Print standard error
            self.fail(result)

    def test(self):
        """
        Execute the build.sh script as part of the test case
        """
        result = self.run_build_script()  # Run the build.sh script

    def tearDown(self):
        """
        Tear down and log completion of the build test
        """
        self.log.info("Build test finished.")
