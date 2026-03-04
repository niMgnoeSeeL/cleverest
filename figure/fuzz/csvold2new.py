#!/usr/bin/env python3

'''
turn old waflgo_{proj}_{SCENARIO}(_withiid).csv with following old columns

issue | commit | idx | final | time to find first crash in ms | first_crash

into new columns, where status is set to 'old'

issue | commit | idx | status | final | first crash | time to find first crash
'''

import argparse
import glob
import os
import numpy as np
import pandas as pd


if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  csv_files = sorted(glob.glob('waflgo_*_*.csv'))
  print(f"Found {len(csv_files)} files: {csv_files}")
  for file in csv_files:
    print(f"Processing {file}")
    df = pd.read_csv(file, sep=r"\s\|\s", engine="python")
    if 'status' in df.columns:
      continue
    df['status'] = 'old'
    # rename column
    df.rename(columns={'first_crash': 'first crash'}, inplace=True)
    df.rename(columns={'time to find first crash in ms': 'time to find first crash'}, inplace=True)
    # set new columns order
    header = 'issue | commit | idx | status | final | first crash | time to find first crash'
    cols = header.split(' | ')
    df = df[cols] 
    # move to $file.old
    os.rename(file, file + '.old')
    np_data = df.to_numpy()  # NOTE: have to convert to numpy for saving csv with multi-char delimiter
    np.savetxt(file, np_data, delimiter=' | ', fmt='%s', header=header, comments='')
  