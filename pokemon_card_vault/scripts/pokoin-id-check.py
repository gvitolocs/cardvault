#!/usr/bin/env python3
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pokoin_id_check import main

if __name__ == "__main__":
    raise SystemExit(main())
