#!/usr/bin/env nextflow


nextflow.enable.dsl = 2

include { CHECK_INPUT                   } from '../subworkflows/local/create_meta'
include { ALIGN_SENTIEON                } from '../subworkflows/local/align_sentieon'
include { SNV_CALLING                   } from '../subworkflows/local/snv_calling'
include { CNV_CALLING                   } from '../subworkflows/local/cnv_calling'
include { BIOMARKERS                    } from '../subworkflows/local/biomarkers'
include { QC                            } from '../subworkflows/local/qc'
include { ADD_TO_DB                     } from '../subworkflows/local/add_to_db'

println(params.genome_file)

csv = file(params.csv)
println(csv)

Channel
    .fromPath(params.csv).splitCsv(header:true)
    .map{ row-> tuple(row.group, row.id, row.type, row.clarity_sample_id, row.clarity_pool_id , row.diagnosis ) }
    .set{ meta_coyote }

// Split bed file in to smaller parts to be used for parallel variant calling
Channel
    .fromPath("${params.regions_bed}")
    .ifEmpty { exit 1, "Regions bed file not found: ${params.regions_bed}" }
    .splitText( by: 1000, file: 'bedpart.bed' )
    .set { beds }

Channel
	.fromPath(params.gatkreffolders)
	.splitCsv(header:true)
	.map{ row-> tuple(row.i, row.refpart) }
	.set{ gatk_ref}


workflow SOLID_GMS {


	CHECK_INPUT ( Channel.fromPath(csv) )
	ALIGN_SENTIEON ( 
		CHECK_INPUT.out.fastq,
		CHECK_INPUT.out.meta
	)
	.set { ch_mapped }
	QC ( 
        ch_mapped.qc_out,
		ch_mapped.bam_lowcov
    )
	.set { ch_qc }
	SNV_CALLING ( 
		ch_mapped.bam_umi.groupTuple(),
		beds,
		CHECK_INPUT.out.meta
	)
	.set { ch_vcf }
	ADD_TO_DB (
		ch_vcf.finished_vcf,
		ch_qc.lowcov.filter { item -> item[1] == 'T' }
	)


}

workflow {
	SOLID_GMS()
}













workflow.onComplete {

	def msg = """\
		Pipeline execution summary
		---------------------------
		Completed at: ${workflow.complete}
		Duration    : ${workflow.duration}
		Success     : ${workflow.success}
		scriptFile  : ${workflow.scriptFile}
		workDir     : ${workflow.workDir}
		exit status : ${workflow.exitStatus}
		errorMessage: ${workflow.errorMessage}
		errorReport :
		"""
		.stripIndent()
	def error = """\
		${workflow.errorReport}
		"""
		.stripIndent()

	base = csv.getBaseName()
	logFile = file("/fs1/results/cron/logs/" + base + ".complete")
	logFile.text = msg
	logFile.append(error)
}