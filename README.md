# nf-vcf2maf: Annotate VCF Files and Generate MAF Files

> [!NOTE]
> This repository is no longer being actively maintained, but the functionality should still work

## Purpose

The purpose of this Nextflow workflow is to annotate variants in VCF files using the Ensembl Variant Effect Predictor (VEP) and convert the annotated VCF file into the [Mutation Annotation Format](https://docs.gdc.cancer.gov/Data/File_Formats/MAF_Format/) (MAF). Unlike VEP-anntotated VCF files, MAF files are generally more useful for downstream applications given their tabular nature. For example, you can easily load them into R (_e.g._ with the [`maftools`](https://www.bioconductor.org/packages/release/bioc/html/maftools.html) package) and/or derive the input files for [cBioPortal](https://www.cbioportal.org/visualize).

**Important:** Please read the [limitations](#known-limitations) listed below.

This repository leverages a [fork of vcf2maf](https://github.com/Sage-Bionetworks-Workflows/vcf2maf) and a [custom container image](https://github.com/Sage-Bionetworks-Workflows/vcf2maf-docker).

## Quickstart

1. Prepare a CSV samplesheet according to the [format](#samplesheet) described below.

    **Example:** Stored locally as `./samplesheet.csv`

    ```csv
    synapse_id  ,sample_parent_id ,merged_parent_id ,study_id ,variant_class ,variant_caller ,is_releasable
    syn87654301 ,syn87654311      ,syn87654321      ,study_x  ,germline      ,deepvariant    ,true
    syn87654302 ,syn87654311      ,syn87654321      ,study_x  ,germline      ,deepvariant    ,false
    syn87654303 ,syn87654311      ,syn87654321      ,study_x  ,germline      ,deepvariant    ,true
    syn87654304 ,syn87654312      ,syn87654321      ,study_x  ,germline      ,mutect2        ,false
    syn87654305 ,syn87654312      ,syn87654321      ,study_x  ,germline      ,mutect2        ,false
    syn87654306 ,syn87654312      ,syn87654321      ,study_x  ,germline      ,mutect2        ,false
    syn87654307 ,syn87654313      ,syn87654322      ,study_y  ,germline      ,deepvariant    ,true
    syn36245848 ,syn87654313      ,syn87654322      ,study_y  ,germline      ,deepvariant    ,true
    ```

2. Create a Nextflow secret called `SYNAPSE_AUTH_TOKEN` with a Synapse personal access token ([docs](#authentication)).

3. Prepare your parameters file. For more details, check out the [Parameters](#parameters) section. Only the `input` parameters is required.

    **Example:** Stored locally as `./params.yml`

    ```yaml
    input: "./samplesheet.csv"
    maf_center: "Sage Bionetworks"
    max_subpop_af: 0.0005
    ```

4. Launch workflow using the [Nextflow CLI](https://nextflow.io/docs/latest/cli.html#run), the [Tower CLI](https://help.tower.nf/latest/cli/), or the [Tower web UI](https://help.tower.nf/latest/launch/launchpad/).

    **Example:** Launched using the Nextflow CLI with Docker enabled

    ```console
    nextflow run sage-bionetworks-workflows/nf-vcf2maf -params-file ./params.yml -profile docker
    ```

5. Explore the MAf files uploaded to Synapse (using the parent IDs listed in the samplesheet).

## Authentication

This workflow takes care of transferring files to and from Synapse. Hence, it requires a secret with a personal access token for authentication. To configure Nextflow with such a token, follow these steps:

1. Generate a personal access token (PAT) on Synapse using [this dashboard](https://www.synapse.org/#!PersonalAccessTokens:). Make sure to enable the `view`, `download`, and `modify` scopes since this workflow both downloads and uploads to Synapse.
2. Create a secret called `SYNAPSE_AUTH_TOKEN` containing a Synapse personal access token using the [Nextflow CLI](https://nextflow.io/docs/latest/secrets.html) or [Nextflow Tower](https://help.tower.nf/latest/secrets/overview/).
3. (Tower only) When launching the workflow, include the `SYNAPSE_AUTH_TOKEN` as a pipeline secret from either your user or workspace secrets.

## Parameters

Check out the [Quickstart](#quickstart) section for example parameter values. You are encouraged to read the [limitations](#known-limitations) listed below because some parameters have not been tested with non-default values.

- **`input`**: (Required) A CSV samplesheet that lists the VCF files that should be processed. See below for the [samplesheet format](#samplesheet).
- **`max_subpop_af`**: Threshold used by vcf2maf for labeling variants with the `common_variant` filter. Specifically, the `common_variant` filter is applied to variants with an allele frequency of at least `max_subpop_af` in one or more gnomAD sub-populations ([source](https://github.com/mskcc/vcf2maf/blob/5ed414428046e71833f454d4b64da6c30362a89b/docs/vep_maf_readme.txt#L116-L120)). This filter is useful for removing false-positive somatic variants. The merged MAF files lack these common variants. Default: `0.0005`.
- **`maf_center`**: Value used in the `Center` MAF column. Default: `"Sage Bionetworks"`.
- **`reference_fasta`**: Reference genome FASTA file used in variant calling. Default: `"s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/Homo_sapiens_assembly38.fasta"`.
- **`reference_fasta_fai`**: Reference genome FASTA index (FAI) file. This shouldn't be needed in most cases since the workflow will automatically pick up on the `.fai` file alongside the `.fasta` file. Default: `"${reference_fasta}.fai"`.
- **`vep_tarball`**: A tarball (ideally compressed) of the VEP cache. Default: `"s3://sage-igenomes/vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz"`.
- **`ncbi_build`**: The NCBI genome build. Passed to `--assembly` in VEP ([source](http://Jul2022.archive.ensembl.org/info/docs/tools/vep/script/vep_options.html)). Default: `"GRCh38"`.
- **`species`**: The species identifier. Passed to `--species` in VEP ([source](http://Jul2022.archive.ensembl.org/info/docs/tools/vep/script/vep_options.html)). Default: `"homo_sapiens"`.

## Inputs

### Samplesheet

The input samplesheet should be in comma-separated values (CSV) format and contain the following columns. **You should avoid using spaces or special characters in any of the columns.** Otherwise, you might run into job caching issues.

1. **`synapse_id`**: Synapse ID of the VCF file
   - Make sure that the Synapse account associated with the personal access token has access to all listed VCF files
2. **`biospecimen_id`**: Biospecimen/sample identifier
    - This value will be used to populate the `Tumor_Sample_Barcode` MAF column
    - **Important:** This value needs to uniquely identify samples within each merged MAF file. See [below](#maf-files) for information on how MAF files are merged.
3. **`sample_parent_id`**: Synapse ID of the folder where the individual sample MAF file will be uploaded
    - Suggestion: The folder that contains the VCF file
4. **`merged_parent_id`**: The Synapse ID of the folder where the merged MAF file will be uploaded
    - Suggestion: The root folder containing the VCF files
    - **Important:** This value should be consistent across VCF files that are expected to be merged. Otherwise, you will end up with artificially split merged MAF files. See [below](#maf-files) for information on how MAF files are merged.
5. **`study_id`**: Study identifier
    - Suggestion: The Synapse ID of the project representing the study if you don’t have shorthand study IDs
6. **`variant_class`**: Whether the VCF file contains somatic or germline mutations
    - **Valid values:** `somatic` or `germline`
7. **`variant_caller`**: Name of the variant caller
8. **`is_releasable`**: Whether the VCF file should be included in the merged MAF file
    - **Valid values:** `true` or `false`

## Outputs

### MAF Files

- Individual sample MAF files
  - Unfiltered (_i.e._ includes all variants regardless of their FILTER status, including those that weren’t deemed high-confidence by the variant caller)
  - File naming: `${biospecimen_id}-${variant_class}-${variant_caller}.maf`
- Merged study MAF files (one for every combination of `study_id`, `variant_class` and `variant_caller`)
  - Filtered (_i.e._ restricted to “releasable” samples and variants where `FILTER == 'PASS'`, which excludes those with common_variant due to any(gnomAD_*_AF) >= 0.0005)
  - File naming: `${study_id}-${variant_class}-${variant_caller}.merged.maf`

## Known Limitations

- This workflow has only been tested with the following parameters:
  - `vep_tarball`: Ensembl VEP 107
  - `species`: `homo_sapiens`
  - `ncbi_build`: `GRCh38`
  - `reference_fasta`: GATK FASTA file

## Benchmarks

### Setup

The following benchmarks were performed with the following setup on an EC2 instance:

```console
# Install tmux for long-running commands
sudo yum install -y tmux

# Install and setup Nextflow
sudo yum install -y java
(cd .local/bin && wget -qO- https://get.nextflow.io | bash)
echo 'export NXF_ENABLE_SECRETS=true' >> ~/.bashrc
source ~/.bashrc
nextflow secrets put -n SYNAPSE_AUTH_TOKEN -v "<synapse-pat>"
mkdir -p $HOME/.nextflow/
echo 'aws.client.anonymous = true' >> $HOME/.nextflow/config

# Download and extract Ensembl VEP cache
mkdir -p $HOME/ref/ $HOME/.vep/
rsync -avr --progress rsync://ftp.ensembl.org/ensembl/pub/release-107/variation/indexed_vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz $HOME/ref/
tar -zvxf $HOME/ref/homo_sapiens_vep_107_GRCh38.tar.gz -C $HOME/.vep/

# Download reference genome FASTA file
mkdir -p $HOME/ref/fasta/
aws --no-sign-request s3 sync s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/ $HOME/ref/fasta/

# Stage reference files in memory
mkdir -p /dev/shm/vep/ /dev/shm/fasta/
sudo mount -o remount,size=25G /dev/shm  # Increase /dev/shm size
rsync -avhP $HOME/.vep/ /dev/shm/vep/
rsync -avhP $HOME/ref/fasta/ /dev/shm/fasta/
```

### Preparing the Ensembl VEP cache

#### Outside of Nextflow

To determine the most efficient way of preparing the VEP cache for vcf2maf, I tried different permutations of downloading the tarball or extracted folder from Ensembl or S3. Here are the individual results:

- **Download tarball using rsync from Ensembl:** 10 min 23 sec
- **Download tarball using AWS CLI from S3:** 3 min 14 sec
- **Extract tarball using `tar` locally:** 6 min 11 sec
- **Download extracted folder using AWS CLI from S3:** 4 min 5 sec

Based on the above results, here are some estimated runtimes:

- **Download tarball from Ensembl and extract locally:** 16 min 34 sec
- **Download tarball from S3 and extract locally:** 9 min 25 sec
- **Download extracted tarball from S3:** 4 min 5 sec

Based on the above estimates, downloading the extracted tarball from S3 seems like the most efficient method followed by downloading the tarball from S3 and extracting locally.

#### Within Nextflow

After benchmarking different methods for downloading VEP cache, I performed various test within a Nextflow run. Note that SHM refers to files being in shared memory (_i.e._ `/dev/shm`).

- **Baseline (all reference files in SHM):** 3 min 43 sec
- **FASTA in S3 and VEP folder in SHM:** 4 min 9 sec
- **FASTA in S3 and VEP folder in non-SHM:** 3 min 43 sec
- **FASTA in S3 and VEP folder in S3:** Over 17 min 7 sec[^1]
- **FASTA in S3 and VEP tarball in non-SHM:** 8 min 39 sec
- **FASTA and VEP tarball in S3:** 8 min 38 sec

The above results showed that downloading the tarball from S3 was the most efficient method. While ~10 minutes is a long time to spend on preparing reference files, it's trivial compared to the actual runtimes of vcf2maf, which can reach 4-5 hours. The benefit is portability, including the ability of running this workflow on Tower.

[^1]: While this was expected to be the most efficient method of downloading the VEP cache, I had to kill the job because it was taking so long. Perhaps the AWS Java SDK isn't as efficient as the AWS CLI for downloading a folder in S3 recursively.
