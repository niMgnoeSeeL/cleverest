#!/usr/bin/env python3

'''
merge waflgo_{proj}_{SCENARIO}(_withiid).csv with following two possible columns into one single csv

issue | commit | idx | final | time to find first crash in ms | first_crash
issue | commit | idx | status | final | first crash | time to find first crash

the new csv should have the following columns:
scenario | subject | issue | commit | idx | status | final | first crash | time to find first crash
'''

import argparse
import glob
import pandas as pd

if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  parser.add_argument('--waflgo', action='store_true')
  args = parser.parse_args()
  if args.waflgo:
    csv_files = sorted(glob.glob("waflgo_*.csv"))
  else:
    csv_files = sorted(glob.glob("postfuzz_*.csv"))
  # csv_files = [f for f in csv_files if "withiid" not in f]
  print(f"Found {len(csv_files)} files: {csv_files}")
  all_dfs = []
  cols = ['scenario', 'subject', 'issue', 'commit', 'idx', 'status', 'final', 'first crash', 'time to find first crash']
  for file in csv_files:
    print(f"Processing {file}")
    # extract scenario and subject from filename
    # waflgo_{proj}_{SCENARIO}(_withiid).csv
    parts = file.split('_')
    if len(parts) < 3:
      print(f"Unexpected filename format: {file}")
      continue
    subject = parts[1]
    scenario = '_'.join(parts[2:]).replace('.csv', '').replace('_withiid', '')
    print(f"Subject: {subject}, Scenario: {scenario}")
    df = pd.read_csv(file, sep=r"\s\|\s", engine="python")
    df['scenario'] = scenario
    df['subject'] = subject
    # rename columns if necessary
    if 'time to find first crash in ms' in df.columns:
      df.rename(columns={'time to find first crash in ms': cols[-1]}, inplace=True)
    if 'first_crash' in df.columns:
      df.rename(columns={'first_crash': cols[-2]}, inplace=True)
    if 'status' not in df.columns:
      df['status'] = 'old'
    # manual correct 'final' for mujs issue 141 BIC commit 832e069 as it always crash before
    # if 'status' not ending with ^ and final is 'X', change final to 'B' as fuzzer already trigger bug after
    df.loc[(df['issue'] == 141) & (df['commit'] == '832e069') & (df['status'].str.startswith('bug')) & (~df['status'].str.endswith('^')) & (df['final'] == 'X'), 'final'] = 'B'
    # reorder columns
    for col in cols:
      if col not in df.columns:
        df[col] = pd.NA
    df = df[cols]
    all_dfs.append(df)
  if all_dfs:
    merged_df = pd.concat(all_dfs, ignore_index=True)
    # sort by scenario, issue
    merged_df.sort_values(by=['scenario', 'issue', 'idx'], inplace=True)
    if args.waflgo:
      merged_df.to_csv("merged_waflgo.csv", index=False, sep='\t')
      print(f"Merged data saved to merged_waflgo.csv")
    else:
      merged_df.to_csv("merged_postfuzz.csv", index=False, sep='\t')
      print(f"Merged data saved to merged_postfuzz.csv")