import os
import pandas as pd
import re


def parse_samtools_stats(file_path):
    sample_name = None
    stats = {}

    with open(file_path, 'r') as f:
        for line in f:
            if line.startswith("# The command line was:"):
                match = re.search(r'dedup/([^/]+)_sorted', line)
                if match:
                    sample_name = match.group(1)
            elif line.startswith("SN"):  # Summary Numbers
                parts = line.strip().split('\t')
                if len(parts) >= 3:
                    key, value = parts[1].strip(), parts[2].strip()
                    stats[key] = value

    if not sample_name:
        print(f"Sample name not found in {file_path}")
        sample_name = os.path.basename(file_path).split('_')[0]

    return {
        "Sample": sample_name,
        "Raw Total Sequences": stats.get("raw total sequences:", "NA"),
        "Reads Mapped": stats.get("reads mapped:", "NA"),
        "Reads Unmapped": stats.get("reads unmapped:", "NA"),
        "Reads Duplicated": stats.get("reads duplicated:", "NA"),
        "Reads MQ0": stats.get("reads MQ0:", "NA"),
        "Average Length": stats.get("average length:", "NA"),
        "Maximum Length": stats.get("maximum length:", "NA"),
        "Average Quality": stats.get("average quality:", "NA"),
        "Insert Size Average": stats.get("insert size average:", "NA"),
        "Insert Size Std Dev": stats.get("insert size standard deviation:", "NA"),
        "Percentage Properly Paired": stats.get("percentage of properly paired reads (%):", "NA"),
        "MapQ 30": "NA"  # Initialisation de la colonne MapQ 30
    }


def extract_mapq30_reads(sample_name, samtools_dir):
    file_path = os.path.join(samtools_dir, f"{sample_name}_sorted_md.q30.txt")
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return "NA"

    with open(file_path, 'r') as f:
        for line in f:
            if line.startswith("SN") and "reads mapped:" in line:
                return line.strip().split('\t')[2]

    return "NA"


def parse_qualimap_results(sample_name, qualimap_dir):
    qualimap_folder = f"{sample_name}_report"
    file_path = os.path.join(
        qualimap_dir, qualimap_folder, "genome_results.txt")
    stats = {}

    if not os.path.exists(file_path):
        print(f"Qualimap file not found for sample {sample_name}")
        return {key: "NA" for key in ["Mean Insert Size", "Std Insert Size", "Median Insert Size", "Mean Mapping Quality", "Mean Coverage", "Std Coverage", "Coverage 1X", "Coverage 5X", "Coverage 10X", "Coverage >15X"]}

    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if "mean insert size =" in line:
                stats["Mean Insert Size"] = line.split("=")[1].strip()
            elif "std insert size =" in line:
                stats["Std Insert Size"] = line.split("=")[1].strip()
            elif "median insert size =" in line:
                stats["Median Insert Size"] = line.split("=")[1].strip()
            elif "mean mapping quality =" in line:
                stats["Mean Mapping Quality"] = line.split("=")[1].strip()
            elif "mean coverageData =" in line:
                stats["Mean Coverage"] = line.split("=")[1].strip()
            elif "std coverageData =" in line:
                stats["Std Coverage"] = line.split("=")[1].strip()
            elif "coverageData >= 1X" in line:
                stats["Coverage 1X"] = re.findall(
                    r"\d+\.\d+", line)[0] if re.findall(r"\d+\.\d+", line) else "NA"
            elif "coverageData >= 5X" in line:
                stats["Coverage 5X"] = re.findall(
                    r"\d+\.\d+", line)[0] if re.findall(r"\d+\.\d+", line) else "NA"
            elif "coverageData >= 10X" in line:
                stats["Coverage 10X"] = re.findall(
                    r"\d+\.\d+", line)[0] if re.findall(r"\d+\.\d+", line) else "NA"
            elif "coverageData >= 15X" in line:
                stats["Coverage >15X"] = re.findall(
                    r"\d+\.\d+", line)[0] if re.findall(r"\d+\.\d+", line) else "NA"

    return stats


def process_directory(samtools_dir, qualimap_dir, output_csv):
    data = []
    for filename in os.listdir(samtools_dir):
        if filename.endswith(".txt") and "_sorted_md.q30" not in filename:
            file_path = os.path.join(samtools_dir, filename)
            sample_data = parse_samtools_stats(file_path)
            sample_name = sample_data["Sample"]
            sample_data["MapQ 30"] = extract_mapq30_reads(
                sample_name, samtools_dir)
            qualimap_data = parse_qualimap_results(sample_name, qualimap_dir)
            sample_data.update(qualimap_data)
            data.append(sample_data)

    df = pd.DataFrame(data)
    ordered_columns = ["Sample", "Raw Total Sequences", "Reads Mapped", "MapQ 30", "Reads Unmapped", "Reads Duplicated", "Reads MQ0", "Average Length", "Maximum Length", "Average Quality", "Insert Size Average", "Insert Size Std Dev",
                       "Percentage Properly Paired", "Mean Insert Size", "Std Insert Size", "Median Insert Size", "Mean Mapping Quality", "Mean Coverage", "Std Coverage", "Coverage 1X", "Coverage 5X", "Coverage 10X", "Coverage >15X"]
    df = df[ordered_columns]
    df.to_csv(output_csv, index=False)
    print(f"Données enregistrées dans {output_csv}")


# Utilisation
samtools_directory = "qc/samtools/"
qualimap_directory = "qc/qualimap_hc/"
destination_csv = "samtools_qualimap_summary.csv"
process_directory(samtools_directory, qualimap_directory, destination_csv)
