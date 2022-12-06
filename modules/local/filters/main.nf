process PON_FILTER {
	publishDir "${params.outdir}/${params.subdir}/vcf", mode: 'copy', overwrite: true
	cpus 1
	time '1h'
	tag "$group"
	memory '32 GB'

	input:
		tuple val(group), val(meta), file(vcf) 
		
	output:
		tuple val(group), val(meta), file("${group}.agg.pon.vcf"), emit: vcf_pon

	script:
        def pons = []
        if( params.freebayes ) { pons.push("freebayes="+params.PON_freebayes) }
        if( params.vardict )   { pons.push("vardict="+params.PON_vardict) }
        if( params.tnscope )   { pons.push("tnscope="+params.PON_tnscope) }
        def pons_str = pons.join(",")
        tumor_idx = meta.type.findIndexOf{ it == 'tumor' || it == 'T' }
        """
        filter_with_pon.pl --vcf $vcf --pons $pons_str --tumor-id ${meta.id[tumor_idx]} > ${group}.agg.pon.vcf
        """
	stub:
		tumor_idx = meta.type.findIndexOf{ it == 'tumor' || it == 'T' }
		"""
		echo ${meta.id[tumor_idx]}
		touch ${group}.agg.pon.vcf
		"""
        
}

process FFPE_PON_FILTER {
	publishDir "${params.outdir}/${params.subdir}/vcf", mode: 'copy', overwrite: true
	cpus 1
	time '1h'
	tag "$group"
	memory '32 GB'

	when:
		params.assay == "solid"

	input:
		tuple val(group), val(meta), file(vcf)
		
	output:
		tuple val(group), val(meta), file("${group}.agg.pon.ponffpe.vcf"), emit: vcf_pon_ffpe

	script:
        def pons = []
        if( params.freebayes ) { pons.push("freebayes="+params.PON_freebayes) }
        if( params.vardict )   { pons.push("vardict="+params.PON_vardict) }
        if( params.tnscope )   { pons.push("tnscope="+params.PON_tnscope) }
        def pons_str = pons.join(",")
        tumor_idx = meta.type.findIndexOf{ it == 'tumor' || it == 'T' }
        """
        filter_with_ffpe_pon.pl --vcf $vcf --pons $pons_str --tumor-id ${meta.id[tumor_idx]} > ${group}.agg.pon.ponffpe.vcf
        """
	stub:
		tumor_idx = meta.type.findIndexOf{ it == 'tumor' || it == 'T' }
		"""
		echo ${meta.id[tumor_idx]}
		touch ${group}.agg.pon.ponffpe.vcf
		"""
        
}

process ANNOTATE_VEP {
	container = params.vepcon
	publishDir "${params.outdir}/${params.subdir}/vcf", mode: 'copy', overwrite: true
	cpus params.cpu_many
	time '1h'
	tag "$group"
    
	input:
		tuple val(group), val(meta), file(vcf)
    
	output:
		tuple val(group), val(meta), file("${group}.agg.pon.vep.vcf"), emit: vcf_vep

	script:
		"""
		vep -i ${vcf} -o ${group}.agg.pon.vep.vcf \\
		--offline --merged --everything --vcf --no_stats \\
		--fork ${task.cpus} \\
		--force_overwrite \\
		--plugin CADD $params.CADD --plugin LoFtool \\
		--fasta $params.VEP_FASTA \\
		--dir_cache $params.VEP_CACHE --dir_plugins $params.VEP_CACHE/Plugins \\
		--distance 200 \\
		--custom $params.GNOMAD,gnomADg,vcf,exact,0,AF_popmax,AF,popmax \\
		--custom $params.COSMIC,COSMIC,vcf,exact,0,CNT \\
		--cache \\
		${params.custom_vep} \\
	"""
	stub:
		"""
		echo ${params.custom_vep} $params.VEP_CACHE
		touch ${group}.agg.pon.vep.vcf
		"""
}

process MARK_GERMLINES {
	publishDir "${params.outdir}/${params.subdir}/vcf", mode: 'copy', overwrite: true
	cpus 2
	time '20m'
	tag "$group"

	input:
		tuple val(group), val(meta), file(vcf) // from vcf_germline.join(meta_germline.groupTuple())

		
	output:
		tuple val(group), val(meta), file("${group}.agg.pon.vep.markgerm.vcf"), emit: vcf_germline


	script:
		if( meta.id.size() >= 2 ) {
			tumor_idx = meta.type.findIndexOf{ it == 'tumor' || it == 'T' }
			normal_idx = meta.type.findIndexOf{ it == 'normal' || it == 'N' }
			"""
			fix_vep_gnomad.pl $vcf > ${group}.agg.pon.vep.fix.vcf
			mark_germlines.pl --vcf ${group}.agg.pon.vep.fix.vcf --tumor-id ${meta.id[tumor_idx]} --normal-id ${meta.id[normal_idx]} --assay $params.assay > ${group}.agg.pon.vep.markgerm.vcf
			"""
		}
		else if( id.size() == 1 ) {
			"""
			fix_vep_gnomad.pl $vcf > ${group}.agg.pon.vep.fix.vcf
			mark_germlines.pl --vcf ${group}.agg.pon.vep.fix.vcf --tumor-id ${id[0]} --assay $params.assay > ${group}.agg.pon.vep.markgerm.vcf
			"""
		}
	stub:
		if( meta.id.size() >= 2 ) {
			tumor_idx = meta.type.findIndexOf{ it == 'tumor' || it == 'T' }
			normal_idx = meta.type.findIndexOf{ it == 'normal' || it == 'N' }
			"""
			echo --tumor-id ${meta.id[tumor_idx]} --normal-id ${meta.id[normal_idx]}
			touch ${group}.agg.pon.vep.markgerm.vcf
			"""
		}
		else if( meta.id.size() == 1 ) {
			"""
			echo ${meta.id[0]}
			touch ${group}.agg.pon.vep.markgerm.vcf
			"""
		}
}

process FILTER_FOR_CNV {
    publishDir "${params.outdir}/${params.subdir}/vcf", mode: 'copy', overwrite: true
	cpus 1
	time '20m'
	tag "$group"

    input:
		tuple val(group), val(meta), file(vcf), val(vc), file(vcf_unfilt)

	output:
		tuple val(group), file("${group}_vardict.germlines.vcf.gz"), file("${group}_vardict.germlines.vcf.gz.tbi"), emit: vcf_only_germline
    
    script:
        """
        germline_for_cnvkit.pl $vcf > ${group}.agg.pon.vep.germline.vcf
		bedtools intersect -a $vcf_unfilt -b ${group}.agg.pon.vep.germline.vcf -header > ${group}_vardict.germlines.vcf
        bgzip ${group}_vardict.germlines.vcf
        tabix ${group}_vardict.germlines.vcf.gz
        """
	stub:
		"""
		echo $vcf $vcf_unfilt
		touch ${group}_vardict.germlines.vcf.gz ${group}_vardict.germlines.vcf.gz.tbi
		"""

}