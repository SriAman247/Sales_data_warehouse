/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/
\set ON_ERROR_STOP on

SELECT clock_timestamp() As batch_start_time \gset
\echo ================================================================
\echo Loading Silver Layer
\echo Batch start time: :batch_start_time
\echo ================================================================

BEGIN;
\echo ----------------------------------------------------------------
\echo Loading CRM Tables
\echo ----------------------------------------------------------------

-- Loading silver.crm_cust_info
Select clock_timestamp() As start_time \gset
\echo Start time: :start_time
\echo Truncating table: silver.crm_cust_info
TRUNCATE TABLE silver.crm_cust_info;
\echo Inserting data into table: silver.crm_cust_info
INSERT INTO silver.crm_cust_info (
			cst_id, 
			cst_key, 
			cst_firstname, 
			cst_lastname, 
			cst_marital_status, 
			cst_gndr,
			cst_create_date
)
SELECT 
cst_id,
cst_key,
TRIM(cst_firstname),
TRIM(cst_lastname),
CASE WHEN cst_marital_status='M' then 'Married'
WHEN cst_marital_status='S' then 'Single'
ELSE 'N/A' END AS cst_marital_status,
CASE WHEN cst_gndr='M' then 'Male'
WHEN cst_gndr='F' then 'Female'
ELSE 'N/A' END AS cst_gndr,
cst_create_date
FROM
(
SELECT *, ROW_NUMBER()OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) AS valid_flag
FROM bronze.crm_cust_info
where cst_id is not null
) As valid
WHERE valid_flag=1;
Select clock_timestamp() as end_time, clock_timestamp()- :'start_time'::timestamptz AS load_duration \gset
\echo End time: :end_time
\echo Load duration: :load_duration

-- Loading silver.crm_prd_info
select clock_timestamp() as start_time \gset
\echo start time: :start_time
\echo Truncating table: silver.crm_prd_info
TRUNCATE Table silver.crm_prd_info;
\echo Inserting data into table: silver.crm_prd_info
INSERT INTO silver.crm_prd_info(
	    prd_id,
    	cat_id,
    	prd_key,
		prd_nm,
		prd_cost,
		prd_line,
		prd_start_dt,
		prd_end_dt
)
SELECT 
prd_id,
REPLACE(SUBSTRING(prd_key,1,5),'-','_') as cat_id,
SUBSTRING(prd_key,7,length(prd_key)) AS prd_key,
prd_nm,
Coalesce(prd_cost,0) as prd_cost,	
Case when Upper(trim(prd_line))='M' Then 'Mountain'
when Upper(trim(prd_line))='R' Then 'Road'
when Upper(trim(prd_line))='T' Then 'Touring'
when Upper(trim(prd_line))='S' Then 'Other Sales'
ELSE 'N/A' END AS prd_line,
Cast(prd_start_dt As DATE) as prd_start_dt,
Cast(LEAD(prd_start_dt)OVER(PARTITION by prd_key ORDER by prd_start_dt)-INTERVAL '1 day' As Date) as prd_end_dt	
FROM bronze.crm_prd_info;
select clock_timestamp()as end_time, clock_timestamp()- :'start_time'::timestamptz as load_duration \gset
\echo End time: :end_time
\echo Load duration: :load_duration 

-- Loading crm_sales_details
Select clock_timestamp() As start_time \gset
\echo Start time: :start_time
\echo Truncating table: silver.crm_sales_details
TRUNCATE TABLE silver.crm_sales_details;
\echo Inserting data into table: silver.crm_sales_details
INSERT INTO silver.crm_sales_details(
	sls_ord_num     ,
    sls_prd_key     ,
    sls_cust_id     ,
    sls_order_dt    ,
    sls_ship_dt     ,
    sls_due_dt      ,
    sls_sales       ,
    sls_quantity    ,
    sls_price    
)
SELECT 
sls_ord_num, 
sls_prd_key, 
sls_cust_id, 
CASE WHEN sls_order_dt<=0 OR LENGTH(sls_order_dt::text) != 8 THEN NULL
ELSE CAST(CAST(sls_order_dt as varchar) As date)
END AS sls_order_dt,
CASE WHEN sls_ship_dt<=0 OR LENGTH(sls_ship_dt::text) != 8 THEN NULL
ELSE CAST(CAST(sls_ship_dt as varchar) As date)
END AS sls_ship_dt,
CASE WHEN sls_due_dt<=0 OR LENGTH(sls_due_dt::text) != 8 THEN NULL
ELSE CAST(CAST(sls_due_dt as varchar) As date)
END AS sls_due_dt,
CASE WHEN sls_sales IS NULL OR sls_sales<=0 OR sls_sales!=sls_quantity*ABS(sls_price)
THEN sls_quantity*ABS(sls_price)
ELSE sls_sales
END AS sls_sales, 
sls_quantity, 
CASE WHEN sls_price IS NULL OR sls_price<=0
THEN sls_sales/NULLIF(sls_quantity,0)
ELSE sls_price
END AS sls_price
FROM bronze.crm_sales_details;
Select clock_timestamp() as end_time, clock_timestamp()- :'start_time'::timestamptz AS load_duration \gset
\echo End time: :end_time
\echo Load duration: :load_duration

\echo ----------------------------------------------------------------
\echo Loading ERP Tables
\echo ----------------------------------------------------------------
-- Loading erp_cust_az12
Select clock_timestamp() As start_time \gset
\echo Start time: :start_time
\echo Truncating table: silver.erp_cust_az12
TRUNCATE TABLE silver.erp_cust_az12;
\echo Inserting data into table: silver.erp_cust_az12
INSERT INTO silver.erp_cust_az12(
	cid,
	bdate,
	gen
)
SELECT
CASE when cid like 'NAS%' THEN SUBSTRING(cid,4,LENGTH(cid))
ELSE cid
END AS cid,
CASE WHEN  bdate > CURRENT_DATE Then null
Else bdate End as bdate,
CASE WHEN UPPER(TRIM(gen))='M' OR UPPER(TRIM(gen))='MALE' then 'Male'
WHEN UPPER(TRIM(gen))='F' OR UPPER(TRIM(gen))='FEMALE' then 'Female'
ELSE 'N/A'
END AS gen
FROM bronze.erp_cust_az12;
Select clock_timestamp() as end_time, clock_timestamp()- :'start_time'::timestamptz AS load_duration \gset
\echo End time: :end_time
\echo Load duration: :load_duration

-- Loading erp_loc_a101
Select clock_timestamp() As start_time \gset
\echo Start time: :start_time
\echo Truncating table: silver.erp_loc_a101
TRUNCATE TABLE silver.erp_loc_a101;
\echo Inserting data into table: silver.erp_loc_a101
INSERT INTO silver.erp_loc_a101(
	cid,
	cntry
)
SELECT REPLACE(cid,'-','') as cid, 
    CASE WHEN TRIM(cntry) ='DE' Then 'Germany'
	WHEN TRIM(cntry) IN ('US','USA') THEN 'United States'
	WHEN TRIM(cntry)='' OR cntry IS null then 'N/A'
	ELSE TRIM(cntry) END AS cntry
FROM bronze.erp_loc_a101;
Select clock_timestamp() as end_time, clock_timestamp()- :'start_time'::timestamptz AS load_duration \gset
\echo End time: :end_time
\echo Load duration: :load_duration

-- Loading erp_px_cat_g1v2
Select clock_timestamp() As start_time \gset
\echo Start time: :start_time
\echo Truncating table: silver.erp_px_cat_g1v2
TRUNCATE TABLE silver.erp_px_cat_g1v2;
\echo Inserting data into table: silver.erp_px_cat_g1v2
INSERT INTO silver.erp_px_cat_g1v2(
id, 
cat, 
subcat, 
maintenance
)
SELECT id, 
cat, 
subcat, 
maintenance
FROM bronze.erp_px_cat_g1v2;	
Select clock_timestamp() as end_time, clock_timestamp()- :'start_time'::timestamptz AS load_duration \gset
\echo End time: :end_time
\echo Load duration: :load_duration

COMMIT;

SELECT clock_timestamp() AS batch_end_time, clock_timestamp() - :'batch_start_time'::timestamptz AS batch_duration \gset
\echo ================================================================
\echo Loading Silver Layer completed
\echo Batch end time: :batch_end_time
\echo Total load duration: :batch_duration
\echo ================================================================

/*
	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END
*/
