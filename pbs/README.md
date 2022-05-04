# Workflow

Assuming you're in this directory:

* Uploading files on to HPC: `rsync -avz --exclude-from=ignore_results.txt .. <hpc>`
  * You may want to also include the argument `--del` to clean up the files on the HPC.
* Downloading files from HPC: `rsync -avz --exclude-from=ignore_results.txt <hpc> ..`
