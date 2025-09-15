#!/usr/bin/env python3

import subprocess
import sys
from pathlib import Path
import pandas as pd
import yaml
import logging
import argparse
from litellm import completion
from pandas.io.formats.style import Styler

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stdout))


# B: bug-revealing, D: behavior difference, R: reach, X: unintended bug, 'N': not even reach
SCORE_MAP = {'B': 3, 'D': 2, 'R': 1, 'X': 0, 'N': 0}

PROMPT_ENHANCE = """You are an expert software developer and security tester.
Please browse the url of bug issue report and bug fixing commit below.
The original commit message may not accurately reflect the nature of the bug and intent of the bugfix. 
Please enhance the commit message so it describes condition to reach/trigger the bug concisely and informatively.
The goal is that seeing the enhanced message it is enough to construct high-quality regression test.
The enhanced message should keep the original message style/structure, preferably a single complete sentence.
If original message contains body, keep it intact, otherwise do NOT add body.
Do NOT directly include original/example test case in the message. Prefer natural language over code/implementation detail unless it is necessary.
Only reply with the enhanced commit message, nothing else.

Issue Report: {url_issue}

Bugfix commit:

{commit_info}
"""

def enhance_msg(url_issue: str, commit_info: str) -> str:
    """Enhance the commit message with additional context."""
    prompt = PROMPT_ENHANCE.format(url_issue=url_issue.strip(), commit_info=commit_info.strip())
    # litellm call gemini api with url context tool
    logger.debug(f"Enhance msg for issue: {url_issue}")
    for _ in range(3):  # Retry up to 3 times
        response = completion(
            messages=[{"role": "user", "content": prompt}],
            model="gemini/gemini-2.5-flash",
            tools=[{"urlContext": {}}],
            reasoning_effort="disable"
        )
        try:
            msg_changed = response.choices[0].message.content.strip()
            logger.debug(f"Got msg: {msg_changed}")
            return msg_changed
        except AttributeError:
            logger.warning("API returned None or invalid response, retrying...")
    logger.error("Failed to get a valid response after 3 retries")
    return "Error: Unable to enhance commit message"

def get_commit_message(repo_path: Path, commit_hash: str, msgonly: bool = True) -> str:
    """Get commit message using git command directly"""
    if msgonly:
        commands = ['git', 'show', '-s', '--format=%B', commit_hash]
    else:
        commands = ['git', 'show', '--first-parent', '--format=%B', commit_hash]
    try:
        # Call git directly to get the commit message
        result = subprocess.run(
            commands,
            capture_output=True, text=True, check=True, cwd=repo_path
        )
        
        # Return the commit message, removing trailing newlines
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error getting commit for {commit_hash}: {e}", file=sys.stderr)
        return f"Error: {e.stderr.strip()}"
    except Exception as e:
        print(f"Exception while getting commit for {commit_hash}: {e}", file=sys.stderr)
        return f"Error: {str(e)}"

def make_hyperlink(value, url):
    """Create a hyperlink formula for Excel."""
    return f'=HYPERLINK("{url}", "{value}")'

def write_yaml(output_rows, output_file_yaml):
    """Write output rows to a YAML file."""
    with open(output_file_yaml, 'w') as f:
        yaml.dump(output_rows, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

def generate_excel_data(df_targets, df_agg, repo_root):
    """Generate Excel data from target and aggregated data."""
    excel_rows = []
    
    for _, row in df_targets.iterrows():
        proj = row['software']
        issue = row['issue']
        commit_bic = row['BIC']
        commit_fix = row['BFC']
        repo_path = repo_root / proj
        url_issue = row['url_issue']
        url_bic = row['url_bic']
        url_fix = row['url_bfc']

        msg_bic = get_commit_message(repo_path, commit_bic)
        msg_fix = get_commit_message(repo_path, commit_fix)
        
        # Use pandas DataFrame for counting success
        df_bic = df_agg[(df_agg['commit'] == commit_bic) & (df_agg['iid'] == issue)]
        df_fix = df_agg[(df_agg['commit'] == commit_fix) & (df_agg['iid'] == issue)]
        # default hyperparam: git_info=FULL, max_iter=5, LLM=gpt-4o-2024-08-06, LLM_temp=0.5, NOFEEDBACK/GENCMD=None
        df_bic_default = df_bic[(df_bic['git_info'] == 'FULL') & (df_bic['max_iter'] == 5) & (df_bic['LLM'] == 'gpt-4o-2024-08-06') & (df_bic['LLM_temp'] == 0.5) & (df_bic['NOFEEDBACK'].isnull()) & (df_bic['GENCMD'].isnull())]
        df_fix_default = df_fix[(df_fix['git_info'] == 'FULL') & (df_fix['max_iter'] == 5) & (df_fix['LLM'] == 'gpt-4o-2024-08-06') & (df_fix['LLM_temp'] == 0.5) & (df_fix['NOFEEDBACK'].isnull()) & (df_fix['GENCMD'].isnull())]
        df_bic_msgonly = df_bic[df_bic['git_info'] == 'MSGONLY']
        df_fix_msgonly = df_fix[df_fix['git_info'] == 'MSGONLY']
        df_fix_enhanced = df_fix[df_fix['git_info'] == 'ENHANCED']
        df_fix_reduced = df_fix[df_fix['git_info'] == 'REDUCED']
        
        def calculate_score_avg(df: pd.DataFrame):
            return df['score'].mean()
            
        def best_result(df):
            # get best result among B > D > R > X > N in all 'final_result'
            for result in ['B', 'D', 'R', 'X', 'N']:
                if result in df['final_result'].values:
                    return result
            return None
            
        result_bic = best_result(df_bic)
        result_fix = best_result(df_fix)
        result_bic_default = best_result(df_bic_default)
        result_fix_default = best_result(df_fix_default)
        result_bic_msgonly = best_result(df_bic_msgonly)
        result_fix_msgonly = best_result(df_fix_msgonly)
        result_fix_enhanced = best_result(df_fix_enhanced)
        result_fix_reduced = best_result(df_fix_reduced)
        score_bic = calculate_score_avg(df_bic)
        score_fix = calculate_score_avg(df_fix)
        score_bic_default = calculate_score_avg(df_bic_default)
        score_fix_default = calculate_score_avg(df_fix_default)
        score_bic_msgonly = calculate_score_avg(df_bic_msgonly)
        score_fix_msgonly = calculate_score_avg(df_fix_msgonly)
        score_fix_enhanced = calculate_score_avg(df_fix_enhanced)
        score_fix_reduced = calculate_score_avg(df_fix_reduced)

        excel_rows.append({
            'proj': proj,
            'issue': issue,  # Keep the plain issue value for now
            'commit_bic': commit_bic,
            'commit_fix': commit_fix,
            'msg_bic': msg_bic,
            'msg_fix': msg_fix,
            'result_bic_default': result_bic_default,
            'score_bic_default': score_bic_default,
            'result_fix_default': result_fix_default,
            'result_fix_msgonly': result_fix_msgonly,
            'result_fix_enhanced': result_fix_enhanced,
            'result_fix_reduced': result_fix_reduced,
            'score_fix_default': score_fix_default,
            'score_fix_msgonly': score_fix_msgonly,
            'score_fix_enhanced': score_fix_enhanced,
            'score_fix_reduced': score_fix_reduced,
            'issue_url': url_issue  # Add the issue URL for hyperlink generation
        })
    
    return excel_rows

def generate_yaml_data(df_targets, df_agg, repo_root, do_enhance=False):
    """Generate YAML data from target and aggregated data."""
    msg_rows = []
    
    for _, row in df_targets.iterrows():
        proj = row['software']
        issue = row['issue']
        commit_bic = row['BIC']
        commit_fix = row['BFC']
        repo_path = repo_root / proj
        url_issue = row['url_issue']
        
        msg_fix = get_commit_message(repo_path, commit_fix)
        commit_info_fix = get_commit_message(repo_path, commit_fix, msgonly=False)
        
        # Use pandas DataFrame for counting success
        df_fix = df_agg[(df_agg['commit'] == commit_fix) & (df_agg['iid'] == issue) & (df_agg['LLM'] != 'deepseek-r1')]
        df_fix_msgonly = df_fix[df_fix['git_info'] == 'MSGONLY']
        df_fix_enhanced = df_fix[df_fix['git_info'] == 'ENHANCED']
        df_fix_reduced = df_fix[df_fix['git_info'] == 'REDUCED']
        
        def calculate_score_avg(df: pd.DataFrame):
            return df['score'].mean()

        def best_result(df: pd.DataFrame) -> str:
            for result in ['B', 'D', 'R', 'X', 'N']:
                if result in df['final_result'].values:
                    return result
            return None
            
        result_fix = best_result(df_fix)
        result_fix_msgonly = best_result(df_fix_msgonly)
        score_fix_msgonly = calculate_score_avg(df_fix_msgonly)
        if not df_fix_enhanced.empty:
            result_fix_enhanced = best_result(df_fix_enhanced)
            score_fix_enhanced = calculate_score_avg(df_fix_enhanced)
        if not df_fix_reduced.empty:
            result_fix_reduced = best_result(df_fix_reduced)
            score_fix_reduced = calculate_score_avg(df_fix_reduced)

        # msgfix_can_enhance = result_fix_msgonly != 'B'
        # msgfix_can_reduce = result_fix_msgonly not in ['N', 'X']
        msgfix_can_enhance = score_fix_msgonly < 3.0  # avg score < 3.0 means not all 'B'
        msgfix_can_reduce = score_fix_msgonly > 0.0  # avg score > 0 means not all 'N'

        # read backup yaml to use existing 'msg_enhanced' there
        def read_yaml(file_path: str, commit: str, field: str) -> str:
            with open(file_path, 'r') as f:
                items: list = yaml.safe_load(f)
                for item in items:
                    if item.get('commit') == commit:
                        return item.get(field, "")
            return ""

        enhanced_msg, reduced_msg = None, None
        logger.debug(f"{issue=}, {result_fix_msgonly=}, {score_fix_msgonly=}, {msgfix_can_enhance=}")
        if msgfix_can_enhance:
            logger.debug(f"Try to first read existing enhanced message for {issue} {commit_fix}")
            enhanced_msg = read_yaml("gemini.yaml.bak", commit_fix, "msg_enhanced")
            if not enhanced_msg and do_enhance:
                logger.debug(f"No existing enhanced message, call LLM to enhance")
                enhanced_msg = enhance_msg(url_issue, commit_info_fix)
        if msgfix_can_reduce:
            logger.debug(f"Try to first read existing reduced message for {issue} {commit_fix}")
            reduced_msg = read_yaml("gemini.yaml.bak", commit_fix, "msg_reduced")
            if not reduced_msg and do_enhance:
                logger.debug(f"No existing reduced message, put original msg for manual edit later")
                reduced_msg = msg_fix
        yaml_item = {
            'proj': proj,
            'issue': issue,
            'commit': commit_fix,
            'scenario': 'FIX',
            'best_result': result_fix,
            'best_result_msgonly': result_fix_msgonly,
            'score_msgonly': float(score_fix_msgonly),
            'msg': msg_fix,
            'msg_enhanced': enhanced_msg,
            'msg_reduced': reduced_msg,
        }
        if msgfix_can_enhance and not df_fix_enhanced.empty:
            yaml_item.update({
                'best_result_enhanced': result_fix_enhanced,
                'score_enhanced': float(score_fix_enhanced),
            })
        if msgfix_can_reduce and not df_fix_reduced.empty:
            yaml_item.update({
                'best_result_reduced': result_fix_reduced,
                'score_reduced': float(score_fix_reduced),
            })
        msg_rows.append(yaml_item)

    return msg_rows

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Enhance commit messages for better bug descriptions')
    parser.add_argument('--enhance', action='store_true', help='Enable message enhancement with LLM')
    args = parser.parse_args()
    
    script_dir = Path(__file__).parent
    figure_dir = script_dir.parent / "figure"
    input_file_targets = figure_dir / "targets.csv"
    input_file_agg = figure_dir / "aggregated_results.csv"
    output_file_csv = script_dir / "msg_success.csv"
    output_file_excel = script_dir / "msg_success.xlsx"
    output_msg_yaml = script_dir / "gemini.yaml"
    repo_root = script_dir.parent

    # Read input CSV and aggregated_results.csv using pandas
    df_targets = pd.read_csv(input_file_targets)
    df_agg = pd.read_csv(input_file_agg)

    # Generate Excel data
    excel_rows = generate_excel_data(df_targets, df_agg, repo_root)
    
    # Create and save Excel file
    df_out = pd.DataFrame(excel_rows)
    df_out.to_csv(output_file_csv, index=False)

    # Apply hyperlinks to the 'issue' column
    df_out['issue'] = df_out.apply(lambda row: make_hyperlink(row['issue'], row['issue_url']), axis=1)
    df_out.drop(columns=['issue_url'], inplace=True)  # Remove the issue_url column

    # Define a function for conditional formatting
    def highlight_scores(row):
        styles = ['']
        if row['score_fix_enhanced'] > row['score_fix_msgonly']:
            styles.append('background-color: green')
        elif row['score_fix_enhanced'] < row['score_fix_msgonly']:
            styles.append('background-color: orange')
        else:
            styles.append('')

        if row['score_fix_reduced'] < row['score_fix_msgonly']:
            styles.append('background-color: green')
        elif row['score_fix_reduced'] > row['score_fix_msgonly']:
            styles.append('background-color: orange')
        else:
            styles.append('')

        return styles

    # Apply conditional formatting
    styled_df = df_out.style.apply(lambda row: highlight_scores(row), axis=1, subset=['score_fix_msgonly', 'score_fix_enhanced', 'score_fix_reduced'])

    # Write to Excel with conditional formatting
    styled_df.to_excel(output_file_excel, index=False, engine='openpyxl')

    # Generate and save YAML data
    msg_rows = generate_yaml_data(df_targets, df_agg, repo_root, do_enhance=args.enhance)
    write_yaml(msg_rows, output_msg_yaml)
    print(f"Generated {output_file_csv}, {output_file_excel}, and {output_msg_yaml} with {len(df_out)} rows")
 
if __name__ == "__main__":
    main()
