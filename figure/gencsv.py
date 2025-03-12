import os
import csv
import sys


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
                statuses = parts[-3].strip()
                final_result = parts[-2].strip()
                if 'behave' in statuses and final_result == 'R':
                  final_result = 'D'  # some data containing 'behave' is determined to 'R' by mistake, should be 'D'
                time = parts[-1].strip().split()[0]
                if final_result == 'X':
                  unintended_bug = 'True'
                else:
                  unintended_bug = 'False'
                results.append((issue, commit, final_result, unintended_bug, time))
        
        return config, results

def main():
    # output file is argv[1] or 'aggregated_results.csv'
    if len(sys.argv) > 1:
        output_csv = sys.argv[1]
    else:
        output_csv = 'aggregated_results.csv'
    summary_files = [f for f in os.listdir('.') if f.startswith('SUMMARY_') and f.endswith('.txt')]
    aggregated_results = []

    print("Found {} summary files".format(len(summary_files)))
    for summary_file in summary_files:
        config, results = parse_summary_file(summary_file)
        for result in results:
            aggregated_results.append([
                summary_file,
                config.get('SCENARIO', ''),
                config.get('GIT_INFO', ''),
                config.get('MAX_ITER', ''),
                config.get('LLM', ''),
                config.get('LLM_TEMP', ''),
                config.get('NOFEEDBACK', ''),
                config.get('GENCMD', ''),
                config.get('RUNFUZZ', ''),
                summary_file.split('_')[1],  # subject
                result[0],   # issue
                result[1],  # commit
                result[2],  # final_result
                result[3],  # unintended_bug
                result[4]   # time
            ])

    # Write to CSV file
    with open(output_csv, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile)
        csvwriter.writerow([
            'file', 'scenario', 'git_info', 'max_iter', 'LLM', 'LLM_temp', 
            'NOFEEDBACK', 'GENCMD', 'RUNFUZZ', 'subject',
            'issue', 'commit', 'final_result', 'unintended_bug', 'time'
        ])
        aggregated_results.sort(key=lambda x: (x[0]))  # Sort by scenario, git_info, and commit
        csvwriter.writerows(aggregated_results)

if __name__ == "__main__":
    main()
