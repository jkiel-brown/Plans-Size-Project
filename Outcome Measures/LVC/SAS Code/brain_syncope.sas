/* ---- Open the saved dataset ---- */
libname outlib "P:\cahpr\jkiel1\Plans Project\Output";

data merged_county_final;
    set outlib.merged_county_final;
run;


/* ================= Brain imaging for syncope: LVC flag, claim-level only ================= */
data merged_county_final;
    set merged_county_final;

    array proc{5} $ hbrchcp1-hbrchcp5;
    array diag{5} $ hbdiag1-hbdiag5;

    /* ---- brain imaging procedure present ---- */
    brain_imaging = 0;
    do i = 1 to 5;
        if proc{i} in ("70450","70460","70470","70551","70552","70553","70554",
                       "70555","70556","70557")
            then brain_imaging = 1;
    end;

    /* ---- syncope diagnosis present (R55) ---- */
    syncope_dx = 0;
    do i = 1 to 5;
        if substr(diag{i},1,3) = "R55" then syncope_dx = 1;
    end;

    /* ---- exclusion diagnosis present anywhere on the claim ---- */
    brain_exclusion_dx = 0;
    do i = 1 to 5;
        if substr(diag{i},1,3) in ("I62","I63","C71","G40","R56","G81","R20","R47","G45") 
            then brain_exclusion_dx = 1;
        if substr(diag{i},1,4) in ("G459","I693","D233","D234","C760","D333","D332","D331","D330") 
            then brain_exclusion_dx = 1;
        if substr(diag{i},1,5) in ("Z8673","D3611","R4182") 
            then brain_exclusion_dx = 1;
        if substr(diag{i},1,2) = "S0" 
            then brain_exclusion_dx = 1;
        if substr(diag{i},1,4) in ("M315","M316") 
            then brain_exclusion_dx = 1;
    end;

    /* ---- final LVC flag ---- */
    if brain_imaging = 1 and syncope_dx = 1 and brain_exclusion_dx = 0 
        then brain_syncope_lvc = 1;
    else brain_syncope_lvc = 0;

    drop i;
run;

/* ================= Beneficiary-level: anyone with at least one LVC brain imaging claim ================= */
proc sql;
    create table bene_lowvalue_brain as
    select bene_id_18900, max(brain_syncope_lvc) as bene_lowvalue_brain_screen
    from merged_county_final
    group by bene_id_18900;
quit;

/* ================= 1. Encounter-level summary ================= */
proc sql;
    create table brain_lvc_encounter_summary as
    select count(*) as N_Total_Encounters,
           sum(brain_syncope_lvc) as N_LVC_Encounters,
           round(100 * calculated N_LVC_Encounters / calculated N_Total_Encounters, 0.1) as Pct_LVC_Encounters
    from merged_county_final;
quit;

proc print data=brain_lvc_encounter_summary noobs label;
    label N_Total_Encounters = "N Total Encounters"
          N_LVC_Encounters   = "N Low-Value Brain Imaging Claims"
          Pct_LVC_Encounters = "% of All Encounters";
run;

/* ================= 2. Beneficiary-level summary (no restriction population) ================= */
proc sql;
    create table brain_lvc_bene_summary as
    select count(distinct bene_id_18900) as N_Total_Benes,
           sum(bene_lowvalue_brain_screen) as N_Bene_LVC,
           round(100 * calculated N_Bene_LVC / calculated N_Total_Benes, 0.1) as Pct_Bene_LVC
    from bene_lowvalue_brain;
quit;

proc print data=brain_lvc_bene_summary noobs label;
    label N_Total_Benes = "N Total Beneficiaries"
          N_Bene_LVC    = "N with >=1 Low-Value Brain Imaging Claim"
          Pct_Bene_LVC  = "% with >=1 Low-Value Claim";
run;

/* ================= 3. Funnel: brain imaging -> syncope present -> no exclusions (final) ================= */
proc sql;
    create table brain_lvc_funnel as
    select 
        (select count(distinct bene_id_18900) from merged_county_final where brain_imaging = 1) 
            as N_Brain_Imaging,
        (select count(distinct bene_id_18900) from merged_county_final where brain_imaging = 1 and syncope_dx = 1) 
            as N_Brain_Imaging_Syncope,
        (select count(distinct bene_id_18900) from merged_county_final where brain_syncope_lvc = 1) 
            as N_LVC_Final
    from merged_county_final (obs=1);
quit;

proc print data=brain_lvc_funnel noobs label;
    label N_Brain_Imaging          = "N Beneficiaries with Brain Imaging Claim"
          N_Brain_Imaging_Syncope  = "N of Those with Syncope Diagnosis (R55)"
          N_LVC_Final              = "N with No Exclusion Diagnosis (Final LVC)";
run;

/* ================= 4. Beneficiary-level rollup with size_of_plan/cat ================= */
proc sql;
    create table bene_brain_lvc_plan as
    select bene_id_18900,
           max(brain_syncope_lvc) as any_brain_lvc_screen,
           max(size_of_plan) as size_of_plan,
           max(cat) as cat
    from merged_county_final
    group by bene_id_18900;
quit;

/* ---- By size_of_plan ---- */
proc sql;
    create table brain_lvc_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(any_brain_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_brain_lvc_plan
    group by size_of_plan;
quit;

proc print data=brain_lvc_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total       = "N Total Individuals"
          N_LVC         = "N with Low-Value Brain Imaging Claim"
          Pct_LVC       = "% with Low-Value Claim";
run;

/* ---- By cat ---- */
proc sql;
    create table brain_lvc_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_brain_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_brain_lvc_plan
    group by cat;
quit;

proc print data=brain_lvc_by_cat noobs label;
    label cat     = "Category"
          N_Total = "N Total Individuals"
          N_LVC   = "N with Low-Value Brain Imaging Claim"
          Pct_LVC = "% with Low-Value Claim";
run;

/* ---- By size_of_plan x cat ---- */
proc sql;
    create table brain_lvc_by_size_cat as
    select size_of_plan, cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_brain_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_brain_lvc_plan
    group by size_of_plan, cat;
quit;

proc print data=brain_lvc_by_size_cat noobs label;
    label size_of_plan = "Plan Size"
          cat           = "Category"
          N_Total       = "N Total Individuals"
          N_LVC         = "N with Low-Value Brain Imaging Claim"
          Pct_LVC       = "% with Low-Value Claim";
run;
