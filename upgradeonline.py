import random
import os
import time

from avocado import Test
from avocado.utils import process, genio

class Upgradeonlinetest(Test):

    proc = None
    cbd_dev_list = []

    def setUp(self):
        self.cbdd_timeout = self.params.get("cbdd_timeout")
        self.cbd_dev = self.params.get('cbd_dev', default=None)
        self.cbd_tests_dir = self.params.get("CBD_TESTS_DIR")
        self.fio_size = self.params.get("fio_size")

        os.chdir(self.cbd_tests_dir)
        if self.cbdd_timeout:
            self.start_cbdd_killer()

    def start_cbdd_killer(self):
        cmd = str("bash %s/utils/start_cbdd_killer.sh %s" % (self.cbd_tests_dir, self.cbdd_timeout))
        self.proc = process.get_sub_process_klass(cmd)(cmd)
        pid = self.proc.start()
        self.log.info("cbdd killer started: pid: %s, %s", pid, self.proc)

    def stop_cbdd_killer(self):
        if not self.proc:
            return

        self.proc.stop(1)
        self.log.info("cbdd killer stopped")

    def test(self):
        cmd = str("fio --name test --rw randwrite --bs 1M --ioengine libaio --filename %s  --direct 1 --numjobs 1 --iodepth 16  --verify md5 --group_reporting --eta-newline 1" % (self.cbd_dev))

        if (self.fio_size):
            cmd = str("%s --size %s" % (cmd, self.fio_size))

        result = process.run(cmd)
        if (result.exit_status):
            self.log.error("fio error")
            self.fail(result)

    def tearDown(self):
        self.stop_cbdd_killer()
