import os
import csv
import sys
import argparse


SCORE_MAP = {'B': 3, 'D': 2, 'R': 1, 'X': 0, 'N': 0}
# some commits trigger unintended bugs without gcov data dumped, manually inspected reachability
# ! gdb --args ./build_before_b7e3bae/bin/jerry ../exp_jerryscript_BIC_GITFULL_ITER5_gpt-4o-2024-08-06_TEMP0.5_250212-1127/INPUT_#5013_b7e3bae_2_gpt-4o-2024-08-06 
# ! gdb --args ./build_after_d7e2125/bin/jerry ../exp_jerryscript_FIX_GITFULL_ITER5_gpt-4o-2024-08-06_TEMP1.0_250218-0140/INPUT_#5117_d7e2125_1_gpt-4o-2024-08-06
MANUAL_MAP = {'832e069': 2, 'b7e3bae': 1, 'd7e2125': 1}

COMMIT2IID = {
    # bic
    "8c27b12": 65,
    "832e069": 141,
    "4c7f6be": 145,
    "3f71a1c": 166,
    "9a82b94": 535,
    "7e3f469": 550,
    "3d35d20": 1282,
    "3cae777": 1289,
    "e674ca6": 1303,
    "aaf2e80": 1305,
    "245abad": 1381,
    # bfc
    "833f82c": 65,
    "6871e5b": 141,
    "f93d245": 145,
    "8b5ba20": 166,
    "d0c3f01": 535,
    "6273df6": 550,
    "4564a00": 1282,
    "efb6868": 1289,
    "a4ca3a9": 1303,
    "907d05a": 1305,
    "1be35ee": 1381,
}

def parse_summary_file(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()
        
        # Parse configuration lines
        config = {}
        for i in range(8):
            try:
              key, value = lines[i].strip().split(': ')
            except ValueError:
              key = lines[i].strip().split(':')[0]
              value = ''
            config[key] = value
        table_hd = lines[10]
        # Parse table lines
        table_lines = lines[11:-2]
        results = []
        for line in table_lines:
            if line.strip():
                parts = line.split('|')
                issue = parts[0].strip()
                commit = parts[-4].strip()
                if issue == commit:  # old SUMMARY does not contain 'issue' column, 0th column is commit, get issue from COMMIT2IID
                  issue = COMMIT2IID.get(commit, 0)
                statuses = parts[-3].strip()
                final_result = parts[-2].strip()
                if 'behave' in statuses and final_result == 'R':
                  final_result = 'D'  # some data containing 'behave' is determined to 'R' by mistake, should be 'D'
                time = parts[-1].strip().split()[0]
                if final_result == 'X':
                  unintended_bug = 'True'
                else:
                  unintended_bug = 'False'
                score = SCORE_MAP[final_result]
                if final_result == 'X' and commit in MANUAL_MAP:
                  score = MANUAL_MAP[commit]
                if config['GIT_INFO'] == 'MSGONLY' and commit == '907d05a' and final_result == 'D':  # poppler #1305 FIX MSGONLY one behave cannot be reproduced, set to 0
                  final_result = 'N'
                  score = 0
                success = 1 if final_result == 'B' else 0
                results.append((commit, final_result, unintended_bug, time, issue, score, success))
        
        return config, results

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Aggregate results from SUMMARY files into a CSV.")
    parser.add_argument('--input', type=str, default='.', help="Directory containing SUMMARY_*.txt files (default: current directory)")
    parser.add_argument('--output', type=str, default='aggregated_results.csv', help="Output CSV file (default: aggregated_results.csv)")
    args = parser.parse_args()

    # Set input and output paths
    input_dir = args.input
    output_csv = args.output

    # Find all SUMMARY_*.txt files in the specified input directory
    summary_files = [os.path.join(input_dir, f) for f in os.listdir(input_dir) if f.startswith('SUMMARY_') and f.endswith('.txt')]
    # recursively find all SUMMARY_*.txt files
    if True:
    # if not summary_files:
      for root, dirs, files in os.walk(input_dir):
        depth = root[len(input_dir):].count(os.sep)
        if depth > 1:  # avoid redundant SUMMARY under exp_*
          continue
        for file in files:
          if file.startswith('SUMMARY_') and file.endswith('.txt'):
            summary_files.append(os.path.join(root, file))
    aggregated_results = []

    print("Found {} summary files".format(len(summary_files)))
    for summary_file in summary_files:
        config, results = parse_summary_file(summary_file)
        summary_filename = os.path.basename(summary_file)
        for result in results:
            aggregated_results.append([
                summary_filename,
                config.get('SCENARIO', ''),
                config.get('GIT_INFO', ''),
                config.get('MAX_ITER', ''),
                config.get('LLM', ''),
                config.get('LLM_TEMP', ''),
                config.get('NOFEEDBACK', ''),
                config.get('GENCMD', ''),
                config.get('RUNFUZZ', ''),
                summary_filename.split('_')[1],  # subject
                result[0],  # commit 
                result[1],  # final_result
                result[2],  # unintended_bug
                result[3],  # time
                result[4],  # iid
                result[5],  # score
                result[6]   # success
            ])

    # Write to CSV file
    with open(output_csv, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile)
        csvwriter.writerow([
            'file', 'scenario', 'git_info', 'max_iter', 'LLM', 'LLM_temp', 
            'NOFEEDBACK', 'GENCMD', 'RUNFUZZ', 'subject',
            # 'issue', 'commit', 'final_result', 'unintended_bug', 'time'
            'commit', 'final_result', 'unintended_bug', 'time', 'iid', 'score', 'success'
        ])
        aggregated_results.sort(key=lambda x: (x[0]))  # Sort by summary filename
        csvwriter.writerows(aggregated_results)

if __name__ == "__main__":
    main()
