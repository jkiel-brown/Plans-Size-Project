/* ---- Open the saved dataset ---- */
libname outlib "P:\cahpr\jkiel1\Plans Project\Output";

data merged_county_final;
    set outlib.merged_county_final;
run;

/* ================= Step 1: raw cervical cancer screening flag, women >65 ================= */
data merged_county_final;
    set merged_county_final;

    array proc{5} $ hbrchcp1-hbrchcp5;

    cerv_screen_raw = 0;

    do i = 1 to 5;
        if proc{i} in ("88141","88142","88143","88147","88148","88150","88152","88153",
                       "88164","88165","88166","88167","88174","88175",
                       "G0123","G0124","G0141","G0143","G0144","G0145","G0147","G0148",
                       "P3000","P3001","G0101","Q0091")
            and hksex = 2 and hkage > 65
            then cerv_screen_raw = 1;
    end;

    drop i;
run;

/* ================= Step 2: earliest screening claim date, per beneficiary ================= */
proc sql;
    create table bene_first_screen as
    select bene_id_18900, min(hbfrom) as first_screen_date format=date9.
    from merged_county_final
    where cerv_screen_raw = 1
    group by bene_id_18900;
quit;

/* ================= Step 3: check ALL claims before that date for exclusion diagnoses ================= */
proc sql;
    create table claims_with_first_screen as
    select a.*, b.first_screen_date
    from merged_county_final as a
    inner join bene_first_screen as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data claims_before_screen_flagged;
    set claims_with_first_screen;

    array diag{5} $ hbdiag1-hbdiag5;

    exclusion_dx = 0;

    if hbfrom < first_screen_date then do;
        do i = 1 to 5;
            if substr(diag{i},1,3) in ("C51","C52","C53","C54","C55","C56","C57","C58")
                then exclusion_dx = 1;
            if substr(diag{i},1,3) = "N87"  then exclusion_dx = 1;
            if substr(diag{i},1,4) = "R876" then exclusion_dx = 1;
            if substr(diag{i},1,5) in ("R8781","R8782") then exclusion_dx = 1;
        end;
    end;

    drop i;
run;

proc sql;
    create table bene_exclusion_before as
    select bene_id_18900, max(exclusion_dx) as exclusion_before
    from claims_before_screen_flagged
    group by bene_id_18900;
quit;

/* ---- Recode: if exclusion found before first screening, zero out ALL that beneficiary's screening flags ---- */
proc sql;
    create table merged_county_final as
    select a.*, coalesce(b.exclusion_before, 0) as exclusion_before
    from merged_county_final as a
    left join bene_exclusion_before as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data merged_county_final;
    set merged_county_final;
    if exclusion_before = 1 then cerv_screen_step2 = 0;
    else cerv_screen_step2 = cerv_screen_raw;
run;

/* ================= Step 3 (per your numbering): unique list of beneficiaries still flagged ================= */
proc sql;
    create table bene_still_screened as
    select distinct bene_id_18900
    from merged_county_final
    where cerv_screen_step2 = 1;
quit;

/* ================= Step 4: match onto Hballenc_updated_2021, keep only matches, check ALL 2021 claims ================= */
data claims_2021_filtered;
    if _n_ = 0 then set bene_still_screened (keep=bene_id_18900);

    if _n_ = 1 then do;
        declare hash hb(dataset:"bene_still_screened(keep=bene_id_18900)");
        hb.defineKey("bene_id_18900");
        hb.defineDone();
    end;

    set claims.Hballenc_updated_2021 (keep=bene_id_18900 hbdiag0-hbdiag4);

    if hb.check() ne 0 then delete;
run;

data claims_2021_flagged;
    set claims_2021_filtered;

    array diag21{5} $ hbdiag0-hbdiag4;

    exclusion_2021 = 0;

    do i = 1 to 5;
        if substr(diag21{i},1,3) in ("C51","C52","C53","C54","C55","C56","C57","C58")
            then exclusion_2021 = 1;
        if substr(diag21{i},1,3) = "N87"  then exclusion_2021 = 1;
        if substr(diag21{i},1,4) = "R876" then exclusion_2021 = 1;
        if substr(diag21{i},1,5) in ("R8781","R8782") then exclusion_2021 = 1;
    end;

    drop i;
run;

proc sql;
    create table bene_exclusion_2021 as
    select distinct bene_id_18900
    from claims_2021_flagged
    where exclusion_2021 = 1;
quit;

/* ================= Step 5: recode -- anyone on the 2021 exclusion list gets ALL screenings set to 0 ================= */
proc sql;
    create table merged_county_final as
    select a.*, 
           case when b.bene_id_18900 is not null then 1 else 0 end as exclusion_2021
    from merged_county_final as a
    left join bene_exclusion_2021 as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data merged_county_final;
    set merged_county_final;
    if exclusion_2021 = 1 then cerv_lowvalue_screen = 0;
    else cerv_lowvalue_screen = cerv_screen_step2;
run;

/* ================= Final: encounter-level and beneficiary-level low-value screening flags ================= */

/* encounter-level: cerv_lowvalue_screen already exists on merged_county_final */

proc sql;
    create table bene_lowvalue_cerv as
    select bene_id_18900, max(cerv_lowvalue_screen) as bene_lowvalue_cerv_screen
    from merged_county_final
    group by bene_id_18900;
quit;




/* ================= 1. Encounter-level summary: LVC screenings out of all encounters ================= */
proc sql;
    create table lvc_encounter_summary as
    select count(*) as N_Total_Encounters,
           sum(cerv_lowvalue_screen) as N_LVC_Encounters,
           round(100 * calculated N_LVC_Encounters / calculated N_Total_Encounters, 0.1) as Pct_LVC_Encounters
    from merged_county_final;
quit;

proc print data=lvc_encounter_summary noobs label;
    label N_Total_Encounters = "N Total Encounters"
          N_LVC_Encounters   = "N Low-Value Cervical Screenings"
          Pct_LVC_Encounters = "% of All Encounters";
run;

/* ================= 2. Beneficiary-level summary: women >65 who had at least one LVC screening ================= */
proc sql;
    create table lvc_bene_summary as
    select count(distinct bene_id_18900) as N_Total_Benes,
           sum(bene_lowvalue_cerv_screen) as N_Bene_LVC,
           round(100 * calculated N_Bene_LVC / calculated N_Total_Benes, 0.1) as Pct_Bene_LVC
    from bene_lowvalue_cerv;
quit;

proc print data=lvc_bene_summary noobs label;
    label N_Total_Benes = "N Unique Beneficiaries"
          N_Bene_LVC    = "N with >=1 Low-Value Cervical Screening"
          Pct_Bene_LVC  = "% with >=1 Low-Value Screening";
run;

/* ================= 3. Funnel: how each exclusion step reduced the beneficiary count ================= */
proc sql;
    create table lvc_funnel as
    select 
        (select count(distinct bene_id_18900) from merged_county_final where cerv_screen_raw = 1) 
            as N_Raw_Screened,
        (select count(distinct bene_id_18900) from merged_county_final where cerv_screen_step2 = 1) 
            as N_After_2022_Exclusion,
        (select count(distinct bene_id_18900) from merged_county_final where cerv_lowvalue_screen = 1) 
            as N_After_2021_Exclusion
    from merged_county_final (obs=1);
quit;

proc print data=lvc_funnel noobs label;
    label N_Raw_Screened          = "N Beneficiaries Screened (Raw)"
          N_After_2022_Exclusion  = "N Remaining After 2022 Lookback Exclusion"
          N_After_2021_Exclusion  = "N Remaining After 2021 Lookback Exclusion (Final LVC)";
run;

/* ================= 4. Beneficiary-level rollup with size_of_plan/cat, for the breakdown tables ================= */
proc sql;
    create table bene_lvc_plan as
    select bene_id_18900,
           max(cerv_lowvalue_screen) as any_lvc_screen,
           max(size_of_plan) as size_of_plan,
           max(cat) as cat
    from merged_county_final
    where hksex = 2 and hkage > 65   /* restrict denominator to the eligible population */
    group by bene_id_18900;
quit;

/* ---- By size_of_plan ---- */
proc sql;
    create table lvc_summary_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(any_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_lvc_plan
    group by size_of_plan;
quit;

proc print data=lvc_summary_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total       = "N Unique Individuals (Women >65)"
          N_LVC         = "N with Low-Value Cervical Screening"
          Pct_LVC       = "% with Low-Value Screening";
run;

/* ---- By cat ---- */
proc sql;
    create table lvc_summary_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_lvc_plan
    group by cat;
quit;

proc print data=lvc_summary_by_cat noobs label;
    label cat     = "Category"
          N_Total = "N Unique Individuals (Women >65)"
          N_LVC   = "N with Low-Value Cervical Screening"
          Pct_LVC = "% with Low-Value Screening";
run;

/* ---- By size_of_plan x cat ---- */
proc sql;
    create table lvc_summary_by_size_cat as
    select size_of_plan, cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_lvc_plan
    group by size_of_plan, cat;
quit;

proc print data=lvc_summary_by_size_cat noobs label;
    label size_of_plan = "Plan Size"
          cat           = "Category"
          N_Total       = "N Unique Individuals (Women >65)"
          N_LVC         = "N with Low-Value Cervical Screening"
          Pct_LVC       = "% with Low-Value Screening";
run;
