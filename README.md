# nf-vcf2maf

Annotate VCF files using VEP and generate MAF files using vcf2maf

## Setup

```console
# Install tmux for long-running commands
sudo yum install -y tmux

# Download Ensembl VEP cache (expands to 22G)
mkdir -p $HOME/ref/ $HOME/.vep/
rsync -avr --progress rsync://ftp.ensembl.org/ensembl/pub/release-107/variation/indexed_vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz $HOME/ref/
tar -zvxf $HOME/ref/homo_sapiens_vep_107_GRCh38.tar.gz -C $HOME/.vep/

# Download reference genome FASTA file
mkdir -p $HOME/ref/fasta/
aws --no-sign-request s3 sync s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/ $HOME/ref/fasta/

# Get example VCF file for testing purposes
mkdir -p $HOME/data
echo "Log into AWS using credentials from JumpCloud"
aws s3 cp s3://ntap-add5-project-tower-bucket/outputs/sarek_syn29793238/VariantCalling/2-001_Plexiform_Neurofibroma/DeepVariant/2-001_Plexiform_Neurofibroma.vcf.gz ~/data/test.vcf.gz
gunzip ~/data/test.vcf.gz
head -n 4000 ~/data/test.vcf ~/data/test-small.vcf

# Install and setup Nextflow
sudo yum install -y java
(cd .local/bin && wget -qO- https://get.nextflow.io | bash)
echo 'export NXF_ENABLE_SECRETS=true' >> ~/.bashrc
source ~/.bashrc
nextflow secrets put -n SYNAPSE_AUTH_TOKEN -v "<synapse-pat>"

# Stage reference files in memory
mkdir -p /dev/shm/vep/ /dev/shm/fasta/
sudo mount -o remount,size=30G /dev/shm  # Increase /dev/shm size
rsync -avhP $HOME/.vep/ /dev/shm/vep/
rsync -avhP $HOME/ref/fasta/ /dev/shm/fasta/
```

## Benchmarks

### Ensembl VEP cache

I want to see what's the fastest way of downloading the VEP cache. Based on the tests below, here are some options:

- Download tarball from Ensembl and extract: 16m34s (10m23s + 6m11s)
- Download tarball from S3 and extract: 9m25s (3m14 + 6m11s)
- Download extracted tarball from S3: 4m5

#### Using rsync with Ensembl's servers

```console
$ time rsync -avr --progress rsync://ftp.ensembl.org/ensembl/pub/release-107/variation/indexed_vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz ./

real	10m23.648s
user	0m50.824s
sys	0m44.770s
```

#### Using S3 with our public bucket

```console
$ time aws --no-sign-request s3 cp s3://sage-igenomes/vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz ./s3-homo_sapiens_vep_107_GRCh38.tar.gz

real	3m14.885s
user	3m31.085s
sys	4m1.697s
```

#### Extracting the tarball

```console
$ time tar -zxf $HOME/ref/homo_sapiens_vep_107_GRCh38.tar.gz -C $HOME/.vep/

real	6m11.087s
user	2m59.190s
sys	0m40.660s
```

#### Downloading the extracted tarball

```console
time aws --no-sign-request s3 sync s3://sage-igenomes/vep_cache/homo_sapiens/107_GRCh38/ ./s3-107_GRCh38/

real	4m5.307s
user	5m13.736s
sys	3m24.302s
```

### Nextflow workflow runs

#### Original (all reference files in `/dev/shm`)

```console
$ time nextflow run ~/nf-vcf2maf/main.nf --input ~/data/test.csv

real	3m43.240s
user	0m29.439s
sys	0m1.415s
```

#### VEP in shm and FASTA in S3

Note that I needed to set `aws.client.anonymous = true` in the Nextflow config.

```console
$ time nextflow run ~/nf-vcf2maf/main.nf --input ~/data/test.csv --reference_fasta s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/Homo_sapiens_assembly38.fasta

real	4m9.529s
user	0m56.803s
sys	0m5.996s
```

#### VEP in non-shm and FASTA in S3

I'm curious about the difference in performance between SHM and non-SHM.

```console
$ time nextflow run ~/nf-vcf2maf/main.nf --input ~/data/test.csv --reference_fasta s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/Homo_sapiens_assembly38.fasta --vep_data ~/.vep/homo_sapiens/107_GRCh38/

real	3m43.073s
user	0m27.599s
sys	0m1.449s
```

#### VEP folder and FASTA in S3

I had to kill this job because there was barely any CPU being used. It seemed stuck on staging the `107_GRCh38/` folder. Maybe Nextflow is more efficient with staging files over folders (compared to the AWS CLI). 

```console
$ time nextflow run ~/nf-vcf2maf/main.nf --input ~/data/test.csv --reference_fasta s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/Homo_sapiens_assembly38.fasta --vep_data s3://sage-igenomes/vep_cache/homo_sapiens/107_GRCh38/

^C

real	17m7.522s
user	2m28.423s
sys	0m38.765s
```

#### VEP tarball in non-shm and FASTA in S3


```console
$ time nextflow run ~/nf-vcf2maf/main.nf --input ~/data/test.csv --reference_fasta s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/Homo_sapiens_assembly38.fasta --vep_data ~/ref/homo_sapiens_vep_107_GRCh38.tar.gz

real	8m39.798s
user	0m29.715s
sys	0m1.455s
```


#### VEP tarball and FASTA in S3


```console
$ time nextflow run ~/nf-vcf2maf/main.nf --input ~/data/test.csv --reference_fasta s3://sage-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/Homo_sapiens_assembly38.fasta --vep_data s3://sage-igenomes/vep_cache/homo_sapiens_vep_107_GRCh38.tar.gz

real	8m38.703s
user	2m47.076s
sys	0m50.287s
```

