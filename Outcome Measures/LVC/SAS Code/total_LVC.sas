/* ================= Open the base dataset ================= */
libname outlib "P:\cahpr\jkiel1\Plans Project\Output";

data merged_county_final;
    set outlib.merged_county_final;
run;

/* ================= Run all 12 LVC measure files in sequence ================= */
%let lvcpath = P:\cahpr\jkiel1\Plans Project\LVC\SAS_Code;

%include "&lvcpath.\cervical_screening.sas";
%include "&lvcpath.\colon_screening.sas";
%include "&lvcpath.\prostate_screening.sas";
%include "&lvcpath.\kidney_dialysis.sas";
%include "&lvcpath.\brain_syncope.sas";
%include "&lvcpath.\head_headache.sas";
%include "&lvcpath.\carotid_syncope.sas";
%include "&lvcpath.\back_imaging.sas";
%include "&lvcpath.\sinus_imaging.sas";
%include "&lvcpath.\vitamind.sas";
%include "&lvcpath.\dxa.sas";
%include "&lvcpath.\hypercoag.sas";

/* ================= Combine all 12 beneficiary-level lists into one composite list ================= */
proc sql;
    create table bene_any_lvc as
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_cerv where bene_lowvalue_cerv_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_colon where bene_lowvalue_colon_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_prostate where bene_lowvalue_prostate_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_kidney where bene_lvc_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_brain where bene_lowvalue_brain_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_head where bene_lowvalue_head_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_carotid where bene_lowvalue_carotid_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_back where bene_lowvalue_back_imaging = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_sinus where bene_lowvalue_sinus_imaging = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_vitd where bene_lowvalue_vitd_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_dxa where bene_lowvalue_dxa_screen = 1
    outer union corr
    select distinct bene_id_18900, 1 as any_lvc from bene_lowvalue_hypercoag where bene_lowvalue_hypercoag_test = 1;
quit;

proc sort data=bene_any_lvc nodupkey;
    by bene_id_18900;
run;

/* ================= Category-level flags (cancer screening / imaging / testing) ================= */
proc sql;
    create table bene_lvc_by_category as
    select bene_id_18900,
           max(cat_flag) as cat_flag
    from (
        select bene_id_18900, "Cancer Screening" as cat_flag from bene_lowvalue_cerv where bene_lowvalue_cerv_screen=1
        outer union corr
        select bene_id_18900, "Cancer Screening" as cat_flag from bene_lowvalue_colon where bene_lowvalue_colon_screen=1
        outer union corr
        select bene_id_18900, "Cancer Screening" as cat_flag from bene_lowvalue_prostate where bene_lowvalue_prostate_screen=1
        outer union corr
        select bene_id_18900, "Cancer Screening" as cat_flag from bene_lowvalue_dxa where bene_lowvalue_dxa_screen=1
        outer union corr
        select bene_id_18900, "Imaging" as cat_flag from bene_lowvalue_kidney where bene_lvc_screen=1
        outer union corr
        select bene_id_18900, "Imaging" as cat_flag from bene_lowvalue_brain where bene_lowvalue_brain_screen=1
        outer union corr
        select bene_id_18900, "Imaging" as cat_flag from bene_lowvalue_head where bene_lowvalue_head_screen=1
        outer union corr
        select bene_id_18900, "Imaging" as cat_flag from bene_lowvalue_carotid where bene_lowvalue_carotid_screen=1
        outer union corr
        select bene_id_18900, "Imaging" as cat_flag from bene_lowvalue_back where bene_lowvalue_back_imaging=1
        outer union corr
        select bene_id_18900, "Imaging" as cat_flag from bene_lowvalue_sinus where bene_lowvalue_sinus_imaging=1
        outer union corr
        select bene_id_18900, "Testing" as cat_flag from bene_lowvalue_vitd where bene_lowvalue_vitd_screen=1
        outer union corr
        select bene_id_18900, "Testing" as cat_flag from bene_lowvalue_hypercoag where bene_lowvalue_hypercoag_test=1
    )
    group by bene_id_18900;
quit;
/* NOTE: a beneficiary with LVC services in multiple categories will only show their first/max category here --
   if you want separate 0/1 flags per category instead (so one beneficiary can be 1 for BOTH cancer screening 
   and imaging simultaneously), let me know and I'll restructure this as three separate binary columns instead. */

/* ================= Merge composite list back onto a clean copy of merged_county_final ================= */
data merged_county_final_composite;
    set outlib.merged_county_final;
run;

proc sql;
    create table merged_county_final_composite as
    select a.*, 
           case when b.bene_id_18900 is not null then 1 else 0 end as any_lvc_service,
           c.cat_flag as lvc_category
    from merged_county_final_composite as a
    left join bene_any_lvc as b on a.bene_id_18900 = b.bene_id_18900
    left join bene_lvc_by_category as c on a.bene_id_18900 = c.bene_id_18900;
quit;


/* ================= Three independent category flags instead of one collapsed category ================= */
proc sql;
    create table bene_lvc_category_flags as
    select bene_id_18900,
           max(case when source_table in ("cerv","colon","prostate","dxa") then 1 else 0 end) as lvc_cancer_screening,
           max(case when source_table in ("kidney","brain","head","carotid","back","sinus") then 1 else 0 end) as lvc_imaging,
           max(case when source_table in ("vitd","hypercoag") then 1 else 0 end) as lvc_testing
    from (
        select bene_id_18900, "cerv" as source_table from bene_lowvalue_cerv where bene_lowvalue_cerv_screen=1
        outer union corr
        select bene_id_18900, "colon" as source_table from bene_lowvalue_colon where bene_lowvalue_colon_screen=1
        outer union corr
        select bene_id_18900, "prostate" as source_table from bene_lowvalue_prostate where bene_lowvalue_prostate_screen=1
        outer union corr
        select bene_id_18900, "dxa" as source_table from bene_lowvalue_dxa where bene_lowvalue_dxa_screen=1
        outer union corr
        select bene_id_18900, "kidney" as source_table from bene_lowvalue_kidney where bene_lvc_screen=1
        outer union corr
        select bene_id_18900, "brain" as source_table from bene_lowvalue_brain where bene_lowvalue_brain_screen=1
        outer union corr
        select bene_id_18900, "head" as source_table from bene_lowvalue_head where bene_lowvalue_head_screen=1
        outer union corr
        select bene_id_18900, "carotid" as source_table from bene_lowvalue_carotid where bene_lowvalue_carotid_screen=1
        outer union corr
        select bene_id_18900, "back" as source_table from bene_lowvalue_back where bene_lowvalue_back_imaging=1
        outer union corr
        select bene_id_18900, "sinus" as source_table from bene_lowvalue_sinus where bene_lowvalue_sinus_imaging=1
        outer union corr
        select bene_id_18900, "vitd" as source_table from bene_lowvalue_vitd where bene_lowvalue_vitd_screen=1
        outer union corr
        select bene_id_18900, "hypercoag" as source_table from bene_lowvalue_hypercoag where bene_lowvalue_hypercoag_test=1
    )
    group by bene_id_18900;
quit;

/* ---- attach the three category flags onto merged_county_final_composite, alongside the existing any_lvc_service ---- */
proc sql;
    create table merged_county_final_composite as
    select a.*, 
           coalesce(b.lvc_cancer_screening, 0) as lvc_cancer_screening,
           coalesce(b.lvc_imaging, 0) as lvc_imaging,
           coalesce(b.lvc_testing, 0) as lvc_testing
    from merged_county_final_composite as a
    left join bene_lvc_category_flags as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;







/* ================= 1. Encounter-level summary ================= */
proc sql;
    create table composite_lvc_encounter_summary as
    select count(*) as N_Total_Encounters,
           sum(any_lvc_service) as N_LVC_Encounters,
           round(100 * calculated N_LVC_Encounters / calculated N_Total_Encounters, 0.1) as Pct_LVC_Encounters
    from merged_county_final_composite;
quit;

proc print data=composite_lvc_encounter_summary noobs label;
    label N_Total_Encounters = "N Total Encounters"
          N_LVC_Encounters   = "N Encounters Flagged for Any LVC Service"
          Pct_LVC_Encounters = "% of All Encounters";
run;

/* ================= 2. Beneficiary-level summary: overall composite rate ================= */
proc sql;
    create table composite_lvc_bene_summary as
    select count(distinct bene_id_18900) as N_Total_Benes,
           sum(any_lvc) as N_Bene_LVC,
           round(100 * calculated N_Bene_LVC / calculated N_Total_Benes, 0.1) as Pct_Bene_LVC
    from (select distinct a.bene_id_18900, coalesce(b.any_lvc,0) as any_lvc
          from merged_county_final_composite as a
          left join bene_any_lvc as b on a.bene_id_18900 = b.bene_id_18900);
quit;

proc print data=composite_lvc_bene_summary noobs label;
    label N_Total_Benes = "N Total Beneficiaries"
          N_Bene_LVC    = "N with >=1 LVC Service (Any of 12 Measures)"
          Pct_Bene_LVC  = "% with >=1 LVC Service";
run;

/* ================= 3. Category breakdown: N and % by cancer screening / imaging / testing ================= */
proc sql;
    create table bene_composite_rollup as
    select distinct bene_id_18900,
           max(lvc_cancer_screening) as lvc_cancer_screening,
           max(lvc_imaging) as lvc_imaging,
           max(lvc_testing) as lvc_testing
    from merged_county_final_composite
    group by bene_id_18900;
quit;

proc sql;
    create table composite_category_summary as
    select count(distinct bene_id_18900) as N_Total_Benes,
           sum(lvc_cancer_screening) as N_Cancer_Screening,
           round(100*calculated N_Cancer_Screening/calculated N_Total_Benes,0.1) as Pct_Cancer_Screening,
           sum(lvc_imaging) as N_Imaging,
           round(100*calculated N_Imaging/calculated N_Total_Benes,0.1) as Pct_Imaging,
           sum(lvc_testing) as N_Testing,
           round(100*calculated N_Testing/calculated N_Total_Benes,0.1) as Pct_Testing
    from bene_composite_rollup;
quit;

proc print data=composite_category_summary noobs label;
    label N_Total_Benes       = "N Total Beneficiaries"
          N_Cancer_Screening  = "N with LVC Cancer Screening"
          Pct_Cancer_Screening= "% with LVC Cancer Screening"
          N_Imaging           = "N with LVC Imaging"
          Pct_Imaging         = "% with LVC Imaging"
          N_Testing           = "N with LVC Testing"
          Pct_Testing         = "% with LVC Testing";
run;

/* ================= 4. Composite rate by size_of_plan, cat, and the combination ================= */
proc sql;
    create table bene_composite_plan as
    select bene_id_18900,
           max(any_lvc_service) as any_lvc_service,
           max(size_of_plan) as size_of_plan,
           max(cat) as cat
    from merged_county_final_composite
    group by bene_id_18900;
quit;

/* ---- By size_of_plan ---- */
proc sql;
    create table composite_lvc_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(any_lvc_service) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_composite_plan
    group by size_of_plan;
quit;

proc print data=composite_lvc_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total       = "N Total Individuals"
          N_LVC         = "N with >=1 LVC Service"
          Pct_LVC       = "% with >=1 LVC Service";
run;

/* ---- By cat ---- */
proc sql;
    create table composite_lvc_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_lvc_service) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_composite_plan
    group by cat;
quit;

proc print data=composite_lvc_by_cat noobs label;
    label cat     = "Category"
          N_Total = "N Total Individuals"
          N_LVC   = "N with >=1 LVC Service"
          Pct_LVC = "% with >=1 LVC Service";
run;

/* ---- By size_of_plan x cat ---- */
proc sql;
    create table composite_lvc_by_size_cat as
    select size_of_plan, cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_lvc_service) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_composite_plan
    group by size_of_plan, cat;
quit;

proc print data=composite_lvc_by_size_cat noobs label;
    label size_of_plan = "Plan Size"
          cat           = "Category"
          N_Total       = "N Total Individuals"
          N_LVC         = "N with >=1 LVC Service"
          Pct_LVC       = "% with >=1 LVC Service";
run;

/* ================= 5. Category rates by size_of_plan (cancer/imaging/testing split by plan size) ================= */
proc sql;
    create table bene_category_plan as
    select bene_id_18900,
           max(lvc_cancer_screening) as lvc_cancer_screening,
           max(lvc_imaging) as lvc_imaging,
           max(lvc_testing) as lvc_testing,
           max(size_of_plan) as size_of_plan,
           max(cat) as cat
    from merged_county_final_composite
    group by bene_id_18900;
quit;

proc sql;
    create table category_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(lvc_cancer_screening) as N_Cancer, round(100*calculated N_Cancer/calculated N_Total,0.1) as Pct_Cancer,
           sum(lvc_imaging) as N_Imaging, round(100*calculated N_Imaging/calculated N_Total,0.1) as Pct_Imaging,
           sum(lvc_testing) as N_Testing, round(100*calculated N_Testing/calculated N_Total,0.1) as Pct_Testing
    from bene_category_plan
    group by size_of_plan;
quit;

proc print data=category_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total = "N Total Individuals"
          N_Cancer = "N Cancer Screening LVC"  Pct_Cancer = "% Cancer Screening LVC"
          N_Imaging = "N Imaging LVC"          Pct_Imaging = "% Imaging LVC"
          N_Testing = "N Testing LVC"          Pct_Testing = "% Testing LVC";
run;

/* ---- Same breakdown by cat ---- */
proc sql;
    create table category_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(lvc_cancer_screening) as N_Cancer, round(100*calculated N_Cancer/calculated N_Total,0.1) as Pct_Cancer,
           sum(lvc_imaging) as N_Imaging, round(100*calculated N_Imaging/calculated N_Total,0.1) as Pct_Imaging,
           sum(lvc_testing) as N_Testing, round(100*calculated N_Testing/calculated N_Total,0.1) as Pct_Testing
    from bene_category_plan
    group by cat;
quit;

proc print data=category_by_cat noobs label;
    label cat = "Category"
          N_Total = "N Total Individuals"
          N_Cancer = "N Cancer Screening LVC"  Pct_Cancer = "% Cancer Screening LVC"
          N_Imaging = "N Imaging LVC"          Pct_Imaging = "% Imaging LVC"
          N_Testing = "N Testing LVC"          Pct_Testing = "% Testing LVC";
run;
