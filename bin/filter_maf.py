#!/usr/bin/env python3

import csv
import sys

input_maf  = sys.argv[1]
output_maf = sys.argv[2]

with (
    open(input_maf, newline='') as infile,
    open(output_maf, "w", newline='') as outfile
):
    reader = csv.DictReader(infile, delimiter='\t')
    writer = csv.DictWriter(outfile, reader.fieldnames, delimiter='\t')
    writer.writeheader()
    for row in reader:
        if row['FILTER'] == 'PASS':
            writer.writerow(row)
