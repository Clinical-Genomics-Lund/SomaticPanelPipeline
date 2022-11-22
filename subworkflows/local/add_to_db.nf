#!/usr/bin/env nextflow

include { COYOTE               } from '../../modules/local/coyote/main'

workflow ADD_TO_DB {
    take: 
        vcf
        meta
        lowcov

    main:

        COYOTE { vcf.join(meta.join(lowcov)).view() }

    emit:
        coyotedone = COYOTE.out.coyote_import
        

}

