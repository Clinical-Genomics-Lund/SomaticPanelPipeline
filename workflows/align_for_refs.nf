#!/usr/bin/env nextflow


nextflow.enable.dsl = 2

include { CHECK_INPUT                   } from '../subworkflows/local/create_meta'
include { ALIGN_SENTIEON                } from '../subworkflows/local/align_sentieon'
include { SAMPLE                        } from '../subworkflows/local/sample'


println(params.genome_file)

csv = file(params.csv)
println(csv)

workflow SPP_ALIGN_REFS {

	// Checks input, creates meta-channel and decides whether data should be downsampled //
	CHECK_INPUT ( Channel.fromPath(csv) )

	// Downsample if meta.sub == value and not false //
	SAMPLE ( CHECK_INPUT.out.fastq )  
	.set{ ch_trim }
	// Do alignment if downsample was false and mix with SAMPLE subworkflow output
	ALIGN_SENTIEON ( 
		ch_trim.fastq_trim,
		CHECK_INPUT.out.meta
	)
	.set { ch_mapped } 
	
}

workflow {
	SPP_ALIGN_REFS()
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