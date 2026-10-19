/* ---- Open the saved dataset ---- */
libname outlib "P:\cahpr\jkiel1\Plans Project\Output";

data merged_county_final;
    set outlib.merged_county_final;
run;

/* ================= Step 1: raw Vitamin D screening flag (age > 65) ================= */
data merged_county_final;
    set merged_county_final;

    array proc{5} $ hbrchcp1-hbrchcp5;

    vitd_screen_raw = 0;
    do i = 1 to 5;
        if proc{i} in ("82306","82307","82652","0038U") and hkage > 65 
            then vitd_screen_raw = 1;
    end;

    drop i;
run;

/* ================= Step 2: flag each claim for osteoporosis/kidney/obesity dx, and fragility sub-components ================= */
data merged_county_final;
    set merged_county_final;

    array proc{5} $ hbrchcp1-hbrchcp5;
    array diag{5} $ hbdiag1-hbdiag5;

    osteoporosis_dx = 0;
    kidney_disease_dx = 0;
    obesity_dx = 0;
    hip_fx_repair_cpt = 0;
    wrist_humerus_fx_dx = 0;
    vertebral_fx_dx = 0;
    upper_ext_imaging_cpt = 0;

    do i = 1 to 5;
        /* osteoporosis */
        if substr(diag{i},1,3) in ("M80","M81") then osteoporosis_dx = 1;
        if substr(diag{i},1,6) = "Z87310" then osteoporosis_dx = 1;

        /* kidney disease */
        if substr(diag{i},1,3) = "N81" then kidney_disease_dx = 1;
        if substr(diag{i},1,3) = "I12" then kidney_disease_dx = 1;
        if substr(diag{i},1,3) = "I13" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "E102" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "E112" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "E082" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "E092" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "E132" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "Z992" then kidney_disease_dx = 1;
        if substr(diag{i},1,5) = "Z9115" then kidney_disease_dx = 1;
        if substr(diag{i},1,4) = "Z491" then kidney_disease_dx = 1;

        /* obesity, excluding E663 */
        if substr(diag{i},1,3) = "E66" and substr(diag{i},1,4) ne "E663" 
            then obesity_dx = 1;

        /* fragility (ii): wrist or proximal humerus fracture diagnosis */
        if substr(diag{i},1,4) in ("S526","S525","S621","S620","S422") 
            then wrist_humerus_fx_dx = 1;

        /* fragility (iii): vertebral fracture diagnosis */
        if substr(diag{i},1,4) in ("S220","S320","M485") then vertebral_fx_dx = 1;
        if substr(diag{i},1,3) = "T08" then vertebral_fx_dx = 1;
    end;

    /* fragility (i): hip fracture repair CPT */
    do i = 1 to 5;
        if "27230" <= proc{i} <= "27248" then hip_fx_repair_cpt = 1;

        /* wrist fracture repair CPT (also satisfies the wrist/humerus fracture component) */
        if proc{i} in ("25600","25605","25609","25611") then wrist_humerus_fx_dx = 1;

        /* humerus fracture repair CPT ranges */
        if "23600" <= proc{i} <= "23630" then wrist_humerus_fx_dx = 1;
        if "23665" <= proc{i} <= "23680" then wrist_humerus_fx_dx = 1;

        /* upper extremity imaging CPT */
        if proc{i} in ("73000","73010","73020","73030","73040","73050",
                       "73060","73070","73080","73085",
                       "73090","73092","73100","73110","73115",
                       "73120","73130","73140",
                       "73200","73201","73202","73206",
                       "73218","73219","73220","73221","73222","73223","73225")
            then upper_ext_imaging_cpt = 1;
    end;

    drop i;
run;

/* ================= Step 3: per-category counts, each needs >= 2 claims INDEPENDENTLY ================= */
proc sql;
    create table bene_osteoporosis_count as
    select bene_id_18900, sum(osteoporosis_dx) as n_osteo_claims
    from merged_county_final
    group by bene_id_18900
    having n_osteo_claims >= 2;
quit;

proc sql;
    create table bene_kidney_count as
    select bene_id_18900, sum(kidney_disease_dx) as n_kidney_claims
    from merged_county_final
    group by bene_id_18900
    having n_kidney_claims >= 2;
quit;

proc sql;
    create table bene_obesity_count as
    select bene_id_18900, sum(obesity_dx) as n_obesity_claims
    from merged_county_final
    group by bene_id_18900
    having n_obesity_claims >= 2;
quit;

/* ================= Step 4: fragility pathway (i) -- hip fracture repair, any single claim ================= */
proc sql;
    create table bene_hip_fx as
    select distinct bene_id_18900
    from merged_county_final
    where hip_fx_repair_cpt = 1;
quit;

/* ================= Step 5: fragility pathway (iii) -- vertebral fracture, any single claim ================= */
proc sql;
    create table bene_vertebral_fx as
    select distinct bene_id_18900
    from merged_county_final
    where vertebral_fx_dx = 1;
quit;

/* ================= Step 6: fragility pathway (ii) -- wrist/humerus fracture + imaging within +/-7 days ================= */
proc sql;
    create table wrist_humerus_claims as
    select bene_id_18900, hbclmid, hbfrom as fx_date format=date9.
    from merged_county_final
    where wrist_humerus_fx_dx = 1;
quit;

proc sql;
    create table imaging_claims as
    select bene_id_18900, hbclmid, hbfrom as img_date format=date9.
    from merged_county_final
    where upper_ext_imaging_cpt = 1;
quit;

proc sql;
    create table bene_wrist_humerus_fx as
    select distinct a.bene_id_18900
    from wrist_humerus_claims as a
    inner join imaging_claims as b
      on a.bene_id_18900 = b.bene_id_18900
    where abs(a.fx_date - b.img_date) <= 7;
quit;

/* ================= Step 7: combine all exclusion pathways into one beneficiary-level list ================= */
proc sql;
    create table bene_vitd_exclusion as
    select distinct bene_id_18900 from bene_osteoporosis_count
    outer union corr
    select distinct bene_id_18900 from bene_kidney_count
    outer union corr
    select distinct bene_id_18900 from bene_obesity_count
    outer union corr
    select distinct bene_id_18900 from bene_hip_fx
    outer union corr
    select distinct bene_id_18900 from bene_vertebral_fx
    outer union corr
    select distinct bene_id_18900 from bene_wrist_humerus_fx;
quit;

proc sort data=bene_vitd_exclusion nodupkey;
    by bene_id_18900;
run;

/* ================= Step 8: final flag -- zero out ALL Vitamin D screenings for excluded beneficiaries ================= */
proc sql;
    create table merged_county_final as
    select a.*, 
           case when b.bene_id_18900 is not null then 1 else 0 end as vitd_exclusion
    from merged_county_final as a
    left join bene_vitd_exclusion as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data merged_county_final;
    set merged_county_final;
    if vitd_screen_raw = 1 and vitd_exclusion = 0 
        then vitd_screen_lvc = 1;
    else vitd_screen_lvc = 0;
run;

/* ================= Beneficiary-level: anyone with at least one LVC Vitamin D screening ================= */
proc sql;
    create table bene_lowvalue_vitd as
    select bene_id_18900, max(vitd_screen_lvc) as bene_lowvalue_vitd_screen
    from merged_county_final
    group by bene_id_18900;
quit;

/* ================= 1. Encounter-level summary ================= */
proc sql;
    create table vitd_lvc_encounter_summary as
    select count(*) as N_Total_Encounters,
           sum(vitd_screen_lvc) as N_LVC_Encounters,
           round(100 * calculated N_LVC_Encounters / calculated N_Total_Encounters, 0.1) as Pct_LVC_Encounters
    from merged_county_final;
quit;

proc print data=vitd_lvc_encounter_summary noobs label;
    label N_Total_Encounters = "N Total Encounters"
          N_LVC_Encounters   = "N Low-Value Vitamin D Screenings"
          Pct_LVC_Encounters = "% of All Encounters";
run;

/* ================= 2. Beneficiary-level summary, restricted to age >65 ================= */
proc sql;
    create table bene_vitd_lvc_elig as
    select bene_id_18900,
           max(vitd_screen_lvc) as bene_vitd_lvc_screen
    from merged_county_final
    where hkage > 65
    group by bene_id_18900;
quit;

proc sql;
    create table vitd_lvc_bene_summary as
    select count(distinct bene_id_18900) as N_Total_Benes,
           sum(bene_vitd_lvc_screen) as N_Bene_LVC,
           round(100 * calculated N_Bene_LVC / calculated N_Total_Benes, 0.1) as Pct_Bene_LVC
    from bene_vitd_lvc_elig;
quit;

proc print data=vitd_lvc_bene_summary noobs label;
    label N_Total_Benes = "N Eligible Beneficiaries (Age >65)"
          N_Bene_LVC    = "N with >=1 Low-Value Vitamin D Screening"
          Pct_Bene_LVC  = "% with >=1 Low-Value Screening";
run;

/* ================= 3. Funnel: raw screening -> after exclusion check (final) ================= */
proc sql;
    create table vitd_lvc_funnel as
    select 
        (select count(distinct bene_id_18900) from merged_county_final where vitd_screen_raw = 1) 
            as N_Raw_Screened,
        (select count(distinct bene_id_18900) from merged_county_final where vitd_screen_raw = 1 and vitd_exclusion = 1) 
            as N_Excluded,
        (select count(distinct bene_id_18900) from merged_county_final where vitd_screen_lvc = 1) 
            as N_LVC_Final
    from merged_county_final (obs=1);
quit;

proc print data=vitd_lvc_funnel noobs label;
    label N_Raw_Screened = "N Beneficiaries Screened (Raw)"
          N_Excluded     = "N Excluded (2+ Osteo/Kidney/Obesity Claims or Fragility Fracture)"
          N_LVC_Final    = "N Remaining (Final LVC)";
run;

/* ================= 4. Beneficiary-level rollup with size_of_plan/cat, restricted to age >65 ================= */
proc sql;
    create table bene_vitd_lvc_plan as
    select bene_id_18900,
           max(vitd_screen_lvc) as any_vitd_lvc_screen,
           max(size_of_plan) as size_of_plan,
           max(cat) as cat
    from merged_county_final
    where hkage > 65
    group by bene_id_18900;
quit;

/* ---- By size_of_plan ---- */
proc sql;
    create table vitd_lvc_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(any_vitd_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_vitd_lvc_plan
    group by size_of_plan;
quit;

proc print data=vitd_lvc_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total       = "N Eligible Individuals (Age >65)"
          N_LVC         = "N with Low-Value Vitamin D Screening"
          Pct_LVC       = "% with Low-Value Screening";
run;

/* ---- By cat ---- */
proc sql;
    create table vitd_lvc_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_vitd_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_vitd_lvc_plan
    group by cat;
quit;

proc print data=vitd_lvc_by_cat noobs label;
    label cat     = "Category"
          N_Total = "N Eligible Individuals (Age >65)"
          N_LVC   = "N with Low-Value Vitamin D Screening"
          Pct_LVC = "% with Low-Value Screening";
run;

/* ---- By size_of_plan x cat ---- */
proc sql;
    create table vitd_lvc_by_size_cat as
    select size_of_plan, cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_vitd_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_vitd_lvc_plan
    group by size_of_plan, cat;
quit;

proc print data=vitd_lvc_by_size_cat noobs label;
    label size_of_plan = "Plan Size"
          cat           = "Category"
          N_Total       = "N Eligible Individuals (Age >65)"
          N_LVC         = "N with Low-Value Vitamin D Screening"
          Pct_LVC       = "% with Low-Value Screening";
run;

/* ================= 5. Exclusion pathway breakdown ================= */
proc sql;
    create table vitd_exclusion_pathway_summary as
    select 
        (select count(distinct bene_id_18900) from bene_osteoporosis_count) as N_Excl_Osteoporosis,
        (select count(distinct bene_id_18900) from bene_kidney_count) as N_Excl_Kidney,
        (select count(distinct bene_id_18900) from bene_obesity_count) as N_Excl_Obesity,
        (select count(distinct bene_id_18900) from bene_hip_fx) as N_Excl_Hip_Fx,
        (select count(distinct bene_id_18900) from bene_vertebral_fx) as N_Excl_Vertebral_Fx,
        (select count(distinct bene_id_18900) from bene_wrist_humerus_fx) as N_Excl_Wrist_Humerus_Fx
    from merged_county_final (obs=1);
quit;

proc print data=vitd_exclusion_pathway_summary noobs label;
    label N_Excl_Osteoporosis      = "Excluded via Osteoporosis (2+ claims)"
          N_Excl_Kidney            = "Excluded via Kidney Disease (2+ claims)"
          N_Excl_Obesity           = "Excluded via Obesity (2+ claims)"
          N_Excl_Hip_Fx            = "Excluded via Hip Fracture Repair"
          N_Excl_Vertebral_Fx      = "Excluded via Vertebral Fracture"
          N_Excl_Wrist_Humerus_Fx  = "Excluded via Wrist/Humerus Fx + Imaging";
run;
