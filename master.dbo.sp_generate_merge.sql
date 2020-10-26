SET NOCOUNT ON
GO

PRINT 'Using Master database'
USE master
GO

PRINT 'Checking for the existence of this procedure'
IF (SELECT OBJECT_ID('sp_generate_merge','P')) IS NOT NULL --means, the procedure already exists
 BEGIN
 PRINT 'Procedure already exists. So, dropping it'
 DROP PROC sp_generate_merge
 END
GO

--Turn system object marking on

CREATE PROC [sp_generate_merge]
(
 @table_name nvarchar(776), -- The table/view for which the MERGE statement will be generated using the existing data. This parameter accepts unquoted single-part identifiers only (e.g. MyTable)
 @target_table nvarchar(776) = NULL, -- Use this parameter to specify a different table name into which the data will be inserted/updated/deleted. This parameter accepts unquoted single-part identifiers (e.g. MyTable) or quoted multi-part identifiers (e.g. [OtherDb].[dbo].[MyTable])
 @from nvarchar(max) = NULL, -- Use this parameter to filter the rows based on a filter condition (using WHERE). Note: To avoid inconsistent ordering of results, including an ORDER BY clause is highly recommended
 @include_values bit = 1, -- When 1, a VALUES clause containing data from @table_name is generated. When 0, data will be sourced directly from @table_name when the MERGE is executed (see example 15 for use case)
 @include_timestamp bit = 0, -- [DEPRECATED] Sql Server does not allow modification of TIMESTAMP datatype
 @debug_mode bit = 0, -- If @debug_mode is set to 1, the SQL statements constructed by this procedure will be printed for later examination
 @schema nvarchar(64) = NULL, -- Use this parameter if you are not the owner of the table
 @ommit_images bit = 0, -- Use this parameter to generate MERGE statement by omitting the 'image' columns
 @ommit_identity bit = 0, -- Use this parameter to omit the identity columns
 @top int = NULL, -- Use this parameter to generate a MERGE statement only for the TOP n rows
 @cols_to_include nvarchar(max) = NULL, -- List of columns to be included in the MERGE statement
 @cols_to_exclude nvarchar(max) = NULL, -- List of columns to be excluded from the MERGE statement
 @cols_to_join_on nvarchar(max) = NULL, -- List of columns needed to JOIN the source table to the target table (useful when @table_name is missing a primary key) 
 @update_only_if_changed bit = 1, -- When 1, only performs an UPDATE operation if an included column in a matched row has changed.
 @hash_compare_column nvarchar(128) = NULL, -- When specified, change detection will be based on a SHA2_256 hash of the source data (the hash value will be stored in this @target_table column for later comparison; see Example 16)
 @delete_if_not_matched bit = 1, -- When 1, deletes unmatched source rows from target, when 0 source rows will only be used to update existing rows or insert new.
 @disable_constraints bit = 0, -- When 1, disables foreign key constraints and enables them after the MERGE statement
 @ommit_computed_cols bit = 1, -- When 1, computed columns will not be included in the MERGE statement
 @ommit_generated_always_cols bit = 1, -- When 1, GENERATED ALWAYS columns will not be included in the MERGE statement
 @include_use_db bit = 1, -- When 1, includes a USE [DatabaseName] statement at the beginning of the generated batch
 @results_to_text bit = 0, -- When 1, outputs results to grid/messages window. When 0, outputs MERGE statement in an XML fragment. When NULL, only the @output OUTPUT parameter is returned.
 @include_rowsaffected bit = 1, -- When 1, a section is added to the end of the batch which outputs rows affected by the MERGE
 @nologo bit = 0, -- When 1, the "About" comment is suppressed from output
 @batch_separator nvarchar(50) = 'GO', -- Batch separator to use. Specify NULL to output all statements within a single batch
 @output nvarchar(max) = null output -- Use this output parameter to return the generated T-SQL batches to the caller (Hint: specify @batch_separator=NULL to output all statements within a single batch)
)
AS
BEGIN

/***********************************************************************************************************
Procedure: sp_generate_merge
 (Adapted by Daniel Nolan for SQL Server 2008+)

Adapted from: sp_generate_inserts (Build 22) 
 (Copyright © 2002 Narayana Vyas Kondreddi. All rights reserved.)

Purpose: To generate a MERGE statement from existing data, which will INSERT/UPDATE/DELETE data based
 on matching primary key values in the source/target table.
 
 The generated statements can be executed to replicate the data in some other location.
 
 Typical use cases:
 * Generate statements for static data tables, store the .SQL file in source control and use 
 it as part of your Dev/Test/Prod deployment. The generated statements are re-runnable, so 
 you can make changes to the file and migrate those changes between environments.
 
 * Generate statements from your Production tables and then run those statements in your 
 Dev/Test environments. Schedule this as part of a SQL Job to keep all of your environments 
 in-sync.
 
 * Enter test data into your Dev environment, and then generate statements from the Dev
 tables so that you can always reproduce your test database with valid sample data.
 

Written by: Narayana Vyas Kondreddi
 http://vyaskn.tripod.com/code
 vyaskn@hotmail.com

 Daniel Nolan
 https://twitter.com/dnlnln
 dan@danere.com


Acknowledgements (sp_generate_merge):
 Christian Lorber -- Contributed hashvalue-based change detection that enables efficient ETL implementations
 https://twitter.com/chlorber

 Nathan Skerl -- StackOverflow answer that provided a workaround for the output truncation problem
 http://stackoverflow.com/a/10489767/266882

 Bill Gibson -- Blog that detailed the static data table use case; the inspiration for this proc
 http://blogs.msdn.com/b/ssdt/archive/2012/02/02/including-data-in-an-sql-server-database-project.aspx
 
 Bill Graziano -- Blog that provided the groundwork for MERGE statement generation
 http://weblogs.sqlteam.com/billg/archive/2011/02/15/generate-merge-statements-from-a-table.aspx 

Acknowledgements (sp_generate_inserts):
 Divya Kalra -- For beta testing
 Mark Charsley -- For reporting a problem with scripting uniqueidentifier columns with NULL values
 Artur Zeygman -- For helping me simplify a bit of code for handling non-dbo owned tables
 Joris Laperre -- For reporting a regression bug in handling text/ntext columns

NOTE: Results can be unpredictable with huge text columns or SQL Server 2000's sql_variant data types

Get Started: Ensure that your SQL client is configured to send results to grid (default SSMS behaviour).
This ensures that the generated MERGE statement can be output in full, getting around SSMS's 4000 nchar limit.
After running this proc, click the hyperlink within the single row returned to copy the generated MERGE statement.

Example 1: To generate a MERGE statement for table 'titles':
 
 EXEC sp_generate_merge 'titles'

Example 2: To generate a MERGE statement for 'titlesCopy' table from 'titles' table:

 EXEC sp_generate_merge 'titles', 'titlesCopy'

Example 3: To generate a MERGE statement for table 'titles' that will unconditionally UPDATE matching rows 
 (ie. not perform a "has data changed?" check prior to going ahead with an UPDATE):
 
 EXEC sp_generate_merge 'titles', @update_only_if_changed = 0

Example 4: To generate a MERGE statement for 'titles' table for only those titles 
 which contain the word 'Computer' in them:
 NOTE: Do not complicate the FROM or WHERE clause here. It's assumed that you are good with T-SQL if you are using this parameter

 EXEC sp_generate_merge 'titles', @from = "from titles where title like '%Computer%' order by title_id"

Example 5: To print the debug information:

 EXEC sp_generate_merge 'titles', @debug_mode = 1

Example 6: If the table is in a different schema to the default, use @schema parameter to specify the schema name
 To use this option, you must have SELECT permissions on that table

 EXEC sp_generate_merge 'Nickstable', @schema = 'Nick'

Example 7: To generate a MERGE statement for the rest of the columns excluding images

 EXEC sp_generate_merge 'imgtable', @ommit_images = 1

Example 8: To generate a MERGE statement excluding (omitting) IDENTITY columns:
 (By default IDENTITY columns are included in the MERGE statement)

 EXEC sp_generate_merge 'mytable', @ommit_identity = 1

Example 9: To generate a MERGE statement for the TOP 10 rows in the table:
 
 EXEC sp_generate_merge 'mytable', @top = 10

Example 10: To generate a MERGE statement with only those columns you want:
 
 EXEC sp_generate_merge 'titles', @cols_to_include = "'title','title_id','au_id'"

Example 11: To generate a MERGE statement by omitting certain columns:
 
 EXEC sp_generate_merge 'titles', @cols_to_exclude = "'title','title_id','au_id'"

Example 12: To avoid checking the foreign key constraints while loading data with a MERGE statement:
 
 EXEC sp_generate_merge 'titles', @disable_constraints = 1

Example 13: To exclude computed columns from the MERGE statement:

 EXEC sp_generate_merge 'MyTable', @ommit_computed_cols = 1

Example 14: To generate a MERGE statement for a table that lacks a primary key:
 
 EXEC sp_generate_merge 'StateProvince', @schema = 'Person', @cols_to_join_on = "'StateProvinceCode'"

Example 15: To generate a statement that MERGEs data directly from the source table to a table in another database:

EXEC sp_generate_merge 'StateProvince', @schema = 'Person', @include_values = 0, @target_table = '[OtherDb].[Person].[StateProvince]'

Example 16: To generate a MERGE statement that will update the target table if the calculated hash value of the source does not match the [Hashvalue] column in the target:

EXEC [DB].dbo.[sp_generate_merge] 
@schema = 'Person', 
@target_table = '[DB].[Person].[StateProvince]', 
@table_name = 'v_StateProvince',
@include_values = 0,   
@hash_compare_column = 'Hashvalue',
@include_rowsaffected = 0,
@nologo = 1,
@cols_to_join_on = "'ID'"

Example 17: To generate and immediately execute a MERGE statement that performs an ETL from a table in one database to another:

DECLARE @sql NVARCHAR(MAX)
EXEC [AdventureWorks2017].dbo.sp_generate_merge @output = @sql output, @results_to_text = null, @schema = 'Person', @table_name = 'AddressType', @include_values = 0, @include_use_db = 0, @batch_separator = null, @target_table = '[AdventureWorks2017_Target].[Person].[AddressType]'
EXEC [AdventureWorks2017].dbo.sp_executesql @sql

Example 18: To generate a MERGE that works with a subset of data from the source table only (e.g. will only INSERT/UPDATE rows that meet certain criteria, and not delete unmatched rows):

SELECT * INTO #CurrencyRateFiltered FROM AdventureWorks2017.Sales.CurrencyRate WHERE ToCurrencyCode = 'AUD';
ALTER TABLE #CurrencyRateFiltered ADD CONSTRAINT PK_Sales_CurrencyRate PRIMARY KEY CLUSTERED ( CurrencyRateID )
EXEC tempdb.dbo.sp_generate_merge @table_name='#CurrencyRateFiltered', @target_table='[AdventureWorks2017].[Sales].[CurrencyRate]', @delete_if_not_matched = 0, @include_use_db = 0;

 
***********************************************************************************************************/

SET NOCOUNT ON


--Making sure user only uses either @cols_to_include or @cols_to_exclude
IF ((@cols_to_include IS NOT NULL) AND (@cols_to_exclude IS NOT NULL))
 BEGIN
 RAISERROR('Use either @cols_to_include or @cols_to_exclude. Do not use both the parameters at once',16,1)
 RETURN -1 --Failure. Reason: Both @cols_to_include and @cols_to_exclude parameters are specified
 END


--Making sure the @cols_to_include, @cols_to_exclude and @cols_to_join_on parameters are receiving values in proper format
IF ((@cols_to_include IS NOT NULL) AND (PATINDEX('''%''',@cols_to_include) = 0))
 BEGIN
 RAISERROR('Invalid use of @cols_to_include property',16,1)
 PRINT 'Specify column names surrounded by single quotes and separated by commas'
 PRINT 'Eg: EXEC sp_generate_merge "titles", @cols_to_include = "''title_id'',''title''"'
 RETURN -1 --Failure. Reason: Invalid use of @cols_to_include property
 END

IF ((@cols_to_exclude IS NOT NULL) AND (PATINDEX('''%''',@cols_to_exclude) = 0))
 BEGIN
 RAISERROR('Invalid use of @cols_to_exclude property',16,1)
 PRINT 'Specify column names surrounded by single quotes and separated by commas'
 PRINT 'Eg: EXEC sp_generate_merge "titles", @cols_to_exclude = "''title_id'',''title''"'
 RETURN -1 --Failure. Reason: Invalid use of @cols_to_exclude property
 END

IF ((@cols_to_join_on IS NOT NULL) AND (PATINDEX('''%''',@cols_to_join_on) = 0))
 BEGIN
 RAISERROR('Invalid use of @cols_to_join_on property',16,1)
 PRINT 'Specify column names surrounded by single quotes and separated by commas'
 PRINT 'Eg: EXEC sp_generate_merge "StateProvince", @schema = "Person", @cols_to_join_on = "''StateProvinceCode''"'
 RETURN -1 --Failure. Reason: Invalid use of @cols_to_join_on property
 END

 IF @hash_compare_column IS NOT NULL AND @update_only_if_changed = 0
 BEGIN
	RAISERROR('Invalid use of @update_only_if_changed property',16,1)
	PRINT 'The @hash_compare_column param is set, however @update_only_if_changed is set to 0. To utilize hash-based change detection, please ensure @update_only_if_changed is set to 1.'
	RETURN -1 --Failure. Reason: Invalid use of @update_only_if_changed property
 END	

 IF @hash_compare_column IS NOT NULL AND @include_values = 1
 BEGIN
	RAISERROR('Invalid use of @include_values',16,1)
	PRINT 'Using @hash_compare_column together with @include_values is currenty unsupported. Our intention is to support this in the future, however for now @hash_compare_column can only be specified when @include_values=0'
	RETURN -1 --Failure. Reason: Invalid use of @include_values property
 END

--Checking to see if the database name is specified along wih the table name
--Your database context should be local to the table for which you want to generate a MERGE statement
--specifying the database name is not allowed
IF (PARSENAME(@table_name,3)) IS NOT NULL
 BEGIN
 RAISERROR('Do not specify the database name. Be in the required database and just specify the table name.',16,1)
 RETURN -1 --Failure. Reason: Database name is specified along with the table name, which is not allowed
 END


DECLARE @Internal_Table_Name NVARCHAR(128)
IF PARSENAME(@table_name,1) LIKE '#%'
BEGIN
	IF DB_NAME() <> 'tempdb'
	BEGIN
		RAISERROR('Incorrect database context. The proc must be executed against [tempdb] when a temporary table is specified.',16,1)
		PRINT 'To resolve, execute the proc in the context of [tempdb], e.g. EXEC tempdb.dbo.sp_generate_merge @table_name=''' + @table_name + ''''
		RETURN -1 --Failure. Reason: Temporary tables cannot be referenced in a user db
	END
	SET @Internal_Table_Name = (SELECT [name] FROM sys.objects WHERE [object_id] = OBJECT_ID(@table_name))
END
ELSE
BEGIN
	SET @Internal_Table_Name = @table_name
END

--Checking for the existence of 'user table' or 'view'
--This procedure is not written to work on system tables
--To script the data in system tables, just create a view on the system tables and script the view instead
IF @schema IS NULL
 BEGIN
 IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @Internal_Table_Name AND (TABLE_TYPE = 'BASE TABLE' OR TABLE_TYPE = 'VIEW') AND TABLE_SCHEMA = SCHEMA_NAME())
 BEGIN
 RAISERROR('User table or view not found.',16,1)
 PRINT 'You may see this error if the specified table is not in your default schema (' + SCHEMA_NAME() + '). In that case use @schema parameter to specify the schema name.'
 PRINT 'Make sure you have SELECT permission on that table or view.'
 RETURN -1 --Failure. Reason: There is no user table or view with this name
 END
 END
ELSE
 BEGIN
 IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @Internal_Table_Name AND (TABLE_TYPE = 'BASE TABLE' OR TABLE_TYPE = 'VIEW') AND TABLE_SCHEMA = @schema)
 BEGIN
 RAISERROR('User table or view not found.',16,1)
 PRINT 'Make sure you have SELECT permission on that table or view.'
 RETURN -1 --Failure. Reason: There is no user table or view with this name 
 END
 END


--Variable declarations
DECLARE @Column_ID int, 
 @Column_List nvarchar(max), 
 @Column_List_For_Update nvarchar(max), 
 @Column_List_For_Check nvarchar(max), 
 @Column_Name nvarchar(128), 
 @Column_Name_Unquoted nvarchar(128), 
 @Data_Type nvarchar(128), 
 @Actual_Values nvarchar(max), --This is the string that will be finally executed to generate a MERGE statement
 @IDN nvarchar(128), --Will contain the IDENTITY column's name in the table
 @Target_Table_For_Output nvarchar(776),
 @Source_Table_Qualified nvarchar(776),
 @Source_Table_For_Output nvarchar(776),
 @sql nvarchar(max),  --SQL statement that will be executed to check existence of [Hashvalue] column in case @hash_compare_column is used
 @checkhashcolumn nvarchar(128),
 @SourceHashColumn bit = 0,
 @b char(1) = char(13)

 IF @hash_compare_column IS NOT NULL  --Check existence of column [Hashvalue] in target table and raise error in case of missing
 BEGIN
 IF @target_table IS NULL
 BEGIN
	SET @target_table = @table_name
 END		
 SET @SQL =
	'SELECT @columnname = column_name
	FROM ' + COALESCE(PARSENAME(@target_table,3),DB_NAME()) + '.INFORMATION_SCHEMA.COLUMNS (NOLOCK)
	WHERE TABLE_NAME = ''' + PARSENAME(@target_table,1) + '''' +
	' AND TABLE_SCHEMA = ' + '''' + COALESCE(@schema, SCHEMA_NAME()) + '''' + ' AND [COLUMN_NAME] = ''' + @hash_compare_column + ''''

	EXECUTE sp_executesql @sql, N'@columnname nvarchar(128) OUTPUT', @columnname = @checkhashcolumn OUTPUT
	IF @checkhashcolumn IS NULL
	BEGIN
	  RAISERROR('Column %s not found ',16,1, @hash_compare_column)
	  PRINT 'The specified @hash_compare_column [' + @hash_compare_column +  '] does not exist in ' + QUOTENAME(@target_table) + '. Please make sure that [' + @hash_compare_column + '] VARBINARY (8000) exits in the target table'
	  RETURN -1 --Failure. Reason: There is no column that can be used as the basis of Hashcompare
	END	

 END
 

--Variable Initialization
SET @IDN = ''
SET @Column_ID = 0
SET @Column_Name = ''
SET @Column_Name_Unquoted = ''
SET @Column_List = ''
SET @Column_List_For_Update = ''
SET @Column_List_For_Check = ''
SET @Actual_Values = ''

--Variable Defaults
IF @target_table IS NOT NULL AND (@target_table LIKE '%.%' OR @target_table LIKE '\[%\]' ESCAPE '\')
BEGIN
 IF NOT @target_table LIKE '\[%\]' ESCAPE '\'
 BEGIN
  RAISERROR('Ambiguous value for @target_table specified. Use QUOTENAME() to ensure the identifer is fully qualified (e.g. [dbo].[Titles] or [OtherDb].[dbo].[Titles]).',16,1)
  RETURN -1 --Failure. Reason: The value could be a multi-part object identifier or it could be a single-part object identifier that just happens to include a period character
 END

 -- If the user has specified the @schema param, but the qualified @target_table they've specified does not include the target schema, then fail validation to avoid any ambiguity
 IF @schema IS NOT NULL AND @target_table NOT LIKE '%.%'
 BEGIN
  RAISERROR('The specified @target_table is missing a schema name (e.g. [dbo].[Titles]).',16,1)
  RETURN -1 --Failure. Reason: Omitting the schema in this scenario is likely a mistake
 END

  SET @Target_Table_For_Output = @target_table 
 END
 ELSE
 BEGIN
 IF @schema IS NULL
 BEGIN
  SET @Target_Table_For_Output = QUOTENAME(COALESCE(@target_table, @table_name))
 END
 ELSE
 BEGIN
  SET @Target_Table_For_Output = QUOTENAME(@schema) + '.' + QUOTENAME(COALESCE(@target_table, @table_name))
 END
END

SET @Source_Table_Qualified = QUOTENAME(COALESCE(@schema,SCHEMA_NAME())) + '.' + QUOTENAME(@Internal_Table_Name)
SET @Source_Table_For_Output = QUOTENAME(COALESCE(@schema,SCHEMA_NAME())) + '.' + QUOTENAME(@table_name)

--To get the first column's ID
SELECT @Column_ID = MIN(ORDINAL_POSITION) 
FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK) 
WHERE TABLE_NAME = @Internal_Table_Name
AND TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())


--Loop through all the columns of the table, to get the column names and their data types
WHILE @Column_ID IS NOT NULL
 BEGIN
 SELECT @Column_Name = QUOTENAME(COLUMN_NAME), 
 @Column_Name_Unquoted = COLUMN_NAME,
 @Data_Type = DATA_TYPE 
 FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK) 
 WHERE ORDINAL_POSITION = @Column_ID
 AND TABLE_NAME = @Internal_Table_Name
 AND TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())


IF @Data_Type IN ('timestamp','rowversion') --SQL Server doesn't allow Timestamp/Rowversion column updates
BEGIN
	GOTO SKIP_LOOP
END

 IF @cols_to_include IS NOT NULL --Selecting only user specified columns
 BEGIN
 IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_include) = 0 
 BEGIN
 GOTO SKIP_LOOP
 END
 END

 IF @cols_to_exclude IS NOT NULL --Selecting only user specified columns
 BEGIN
 IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_exclude) <> 0 
 BEGIN
 GOTO SKIP_LOOP
 END
 END

 --Making sure to output SET IDENTITY_INSERT ON/OFF in case the table has an IDENTITY column
 IF (SELECT COLUMNPROPERTY( OBJECT_ID(@Source_Table_Qualified),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsIdentity')) = 1 
 BEGIN
 IF @ommit_identity = 0 --Determing whether to include or exclude the IDENTITY column
 SET @IDN = @Column_Name
 ELSE
 GOTO SKIP_LOOP 
 END
 
 --Making sure whether to output computed columns or not
 IF @ommit_computed_cols = 1
 BEGIN
 IF (SELECT COLUMNPROPERTY( OBJECT_ID(@Source_Table_Qualified),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsComputed')) = 1 
 BEGIN
 PRINT 'Warning: The ' + @Column_Name + ' computed column will be excluded from the MERGE statement. Specify @ommit_computed_cols = 0 to include computed columns.'
 GOTO SKIP_LOOP 
 END
 END

 --Skip this column if it is the GENERATED ALWAYS type, unless the user specifically wants those types of columns included
 IF @ommit_generated_always_cols = 1
 IF ISNULL((SELECT COLUMNPROPERTY( OBJECT_ID(@Source_Table_Qualified),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'GeneratedAlwaysType')), 0) <> 0
 BEGIN
 PRINT 'Warning: The ' + @Column_Name + ' GENERATED ALWAYS column will be excluded from the MERGE statement. Specify @ommit_generated_always_cols = 0 to include GENERATED ALWAYS columns.'
 GOTO SKIP_LOOP 
 END

 --make sure if source table already contains @hash_compare_column to avoid being doubled in UPDATE clause
 IF  @hash_compare_column IS NOT NULL AND @Column_Name = QUOTENAME(@hash_compare_column)
 BEGIN
	SET @SourceHashColumn = 1
 END
 
 --Tables with columns of IMAGE data type are not supported for obvious reasons
 IF(@Data_Type in ('image'))
 BEGIN
 IF (@ommit_images = 0)
 BEGIN
 RAISERROR('Tables with image columns are not supported.',16,1)
 PRINT 'Use @ommit_images = 1 parameter to generate a MERGE for the rest of the columns.'
 RETURN -1 --Failure. Reason: There is a column with image data type
 END
 ELSE
 BEGIN
 GOTO SKIP_LOOP
 END
 END

 --Determining the data type of the column and depending on the data type, the VALUES part of
 --the MERGE statement is generated. Care is taken to handle columns with NULL values. Also
 --making sure, not to lose any data from flot, real, money, smallmomey, datetime columns
 SET @Actual_Values = @Actual_Values +
 CASE 
 WHEN @Data_Type IN ('char','nchar') 
 THEN 
 'COALESCE(''N'''''' + REPLACE(RTRIM(' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('varchar','nvarchar') 
 THEN 
 'COALESCE(''N'''''' + REPLACE(' + @Column_Name + ','''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('datetime','smalldatetime','datetime2','date', 'datetimeoffset') 
 THEN 
 'COALESCE('''''''' + RTRIM(CONVERT(char,' + @Column_Name + ',127))+'''''''',''NULL'')'
 WHEN @Data_Type IN ('uniqueidentifier') 
 THEN 
 'COALESCE(''N'''''' + REPLACE(CONVERT(char(36),RTRIM(' + @Column_Name + ')),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('text') 
 THEN 
 'COALESCE(''N'''''' + REPLACE(CONVERT(varchar(max),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')' 
 WHEN @Data_Type IN ('ntext') 
 THEN 
 'COALESCE('''''''' + REPLACE(CONVERT(nvarchar(max),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')' 
 WHEN @Data_Type IN ('xml') 
 THEN 
 'COALESCE('''''''' + REPLACE(CONVERT(nvarchar(max),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')' 
 WHEN @Data_Type IN ('binary','varbinary') 
 THEN 
 'COALESCE(RTRIM(CONVERT(varchar(max),' + @Column_Name + ', 1)),''NULL'')' 
 WHEN @Data_Type IN ('float','real','money','smallmoney')
 THEN
 'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' + @Column_Name + ',2)' + ')),''NULL'')' 
 WHEN @Data_Type IN ('hierarchyid')
 THEN 
  'COALESCE(''hierarchyid::Parse(''+'''''''' + LTRIM(RTRIM(' + 'CONVERT(char, ' + @Column_Name + ')' + '))+''''''''+'')'',''NULL'')' 
 WHEN @Data_Type IN ('geography')
 THEN
  'COALESCE(''geography::STGeomFromText(''+'''''''' + LTRIM(RTRIM(' + 'CONVERT(nvarchar(max),' + @Column_Name + ')' + '))+''''''''+'', 4326)'',''NULL'')' 
 WHEN @Data_Type IN ('geometry')
 THEN
  'COALESCE(''geometry::Parse(''+'''''''' + LTRIM(RTRIM(' + 'CONVERT(nvarchar(max),' + @Column_Name + ')' + '))+''''''''+'')'',''NULL'')' 
 ELSE 
 'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' + @Column_Name + ')' + ')),''NULL'')' 
 END + '+' + ''',''' + ' + '
 
 --Generating the column list for the MERGE statement
 SET @Column_List = @Column_List +  
 CASE WHEN @hash_compare_column IS NOT NULL AND @Column_Name = QUOTENAME(@hash_compare_column)
 THEN ''
 ELSE @Column_Name + ',' END
 
 --Don't update Primary Key or Identity columns
 IF NOT EXISTS(
 SELECT 1
 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk ,
 INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
 WHERE pk.TABLE_NAME = @Internal_Table_Name
 AND pk.TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
 AND CONSTRAINT_TYPE = 'PRIMARY KEY'
 AND c.TABLE_NAME = pk.TABLE_NAME
 AND c.TABLE_SCHEMA = pk.TABLE_SCHEMA
 AND c.CONSTRAINT_NAME = pk.CONSTRAINT_NAME
 AND c.COLUMN_NAME = @Column_Name_Unquoted 
 )
 BEGIN
  SET @Column_List_For_Update = @Column_List_For_Update + '[Target].' + @Column_Name + ' = [Source].' + @Column_Name + ', ' + @b + '  '
 SET @Column_List_For_Check = @Column_List_For_Check +
 CASE @Data_Type 
 WHEN 'text' THEN CHAR(10) + CHAR(9) + 'NULLIF(CAST([Source].' + @Column_Name + ' AS VARCHAR(MAX)), CAST([Target].' + @Column_Name + ' AS VARCHAR(MAX))) IS NOT NULL OR NULLIF(CAST([Target].' + @Column_Name + ' AS VARCHAR(MAX)), CAST([Source].' + @Column_Name + ' AS VARCHAR(MAX))) IS NOT NULL OR '
 WHEN 'ntext' THEN CHAR(10) + CHAR(9) + 'NULLIF(CAST([Source].' + @Column_Name + ' AS NVARCHAR(MAX)), CAST([Target].' + @Column_Name + ' AS NVARCHAR(MAX))) IS NOT NULL OR NULLIF(CAST([Target].' + @Column_Name + ' AS NVARCHAR(MAX)), CAST([Source].' + @Column_Name + ' AS NVARCHAR(MAX))) IS NOT NULL OR ' 
 WHEN 'geography' THEN CHAR(10) + CHAR(9) + '((NOT ([Source].' + @Column_Name + ' IS NULL AND [Target].' + @Column_Name + ' IS NULL)) AND ISNULL(ISNULL([Source].' + @Column_Name + ', geography::[Null]).STEquals([Target].' + @Column_Name + '), 0) = 0) OR '
 WHEN 'geometry' THEN CHAR(10) + CHAR(9) + '((NOT ([Source].' + @Column_Name + ' IS NULL AND [Target].' + @Column_Name + ' IS NULL)) AND ISNULL(ISNULL([Source].' + @Column_Name + ', geometry::[Null]).STEquals([Target].' + @Column_Name + '), 0) = 0) OR '
 ELSE CHAR(10) + CHAR(9) + 'NULLIF([Source].' + @Column_Name + ', [Target].' + @Column_Name + ') IS NOT NULL OR NULLIF([Target].' + @Column_Name + ', [Source].' + @Column_Name + ') IS NOT NULL OR '
 END 
 END

 SKIP_LOOP: --The label used in GOTO

 SELECT @Column_ID = MIN(ORDINAL_POSITION) 
 FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK) 
 WHERE TABLE_NAME = @Internal_Table_Name
 AND TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
 AND ORDINAL_POSITION > @Column_ID

 END --Loop ends here!


--To get rid of the extra characters that got concatenated during the last run through the loop
IF LEN(@Column_List_For_Update) <> 0
 BEGIN
 SET @Column_List_For_Update = ' ' + LEFT(@Column_List_For_Update,len(@Column_List_For_Update) - 3)
 END

IF LEN(@Column_List_For_Check) <> 0
 BEGIN
 SET @Column_List_For_Check = LEFT(@Column_List_For_Check,len(@Column_List_For_Check) - 3)
 END

SET @Actual_Values = LEFT(@Actual_Values,len(@Actual_Values) - 6)

SET @Column_List = LEFT(@Column_List,len(@Column_List) - 1)
IF LEN(LTRIM(@Column_List)) = 0
 BEGIN
 RAISERROR('No columns to select. There should at least be one column to generate the output',16,1)
 RETURN -1 --Failure. Reason: Looks like all the columns are ommitted using the @cols_to_exclude parameter
 END


--Get the join columns ----------------------------------------------------------
DECLARE @PK_column_list NVARCHAR(max)
DECLARE @PK_column_joins NVARCHAR(max)
SET @PK_column_list = ''
SET @PK_column_joins = ''

IF ISNULL(@cols_to_join_on, '') = '' -- Use primary key of the source table as the basis of MERGE joins, if no join list is specified
BEGIN
	SELECT @PK_column_list = @PK_column_list + '[' + c.COLUMN_NAME + '], '
	, @PK_column_joins = @PK_column_joins + '[Target].[' + c.COLUMN_NAME + '] = [Source].[' + c.COLUMN_NAME + '] AND '
	FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk ,
	INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
	WHERE pk.TABLE_NAME = @Internal_Table_Name
	AND pk.TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
	AND CONSTRAINT_TYPE = 'PRIMARY KEY'
	AND c.TABLE_NAME = pk.TABLE_NAME
	AND c.TABLE_SCHEMA = pk.TABLE_SCHEMA
	AND c.CONSTRAINT_NAME = pk.CONSTRAINT_NAME
END
ELSE
BEGIN
	SELECT @PK_column_list = @PK_column_list + '[' + c.COLUMN_NAME + '], '
	, @PK_column_joins = @PK_column_joins + '([Target].[' + c.COLUMN_NAME + '] = [Source].[' + c.COLUMN_NAME + ']' + CASE WHEN c.IS_NULLABLE='YES' THEN ' OR ([Target].[' + c.COLUMN_NAME + '] IS NULL AND [Source].[' + c.COLUMN_NAME + '] IS NULL)' ELSE '' END + ') AND '
	FROM INFORMATION_SCHEMA.COLUMNS AS c
	WHERE @cols_to_join_on LIKE '%''' + c.COLUMN_NAME + '''%'
	AND c.TABLE_NAME = @Internal_Table_Name
	AND c.TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
END

IF ISNULL(@PK_column_list, '') = '' 
BEGIN
	RAISERROR('Table does not have a primary key from which to generate the join clause(s) and/or a valid @cols_to_join_on has not been specified. Either add a primary key/composite key to the table or specify the @cols_to_join_on parameter.',16,1)
	RETURN -1 --Failure. Reason: looks like table doesn't have any primary keys
END

SET @PK_column_list = LEFT(@PK_column_list, LEN(@PK_column_list) -1)
SET @PK_column_joins = LEFT(@PK_column_joins, LEN(@PK_column_joins) -4)


--Forming the final string that will be executed, to output the a MERGE statement
SET @Actual_Values = 
 'SELECT ' + 
 CASE WHEN @top IS NULL OR @top < 0 THEN '' ELSE ' TOP ' + LTRIM(STR(@top)) + ' ' END + 
 '''' + 
 ' '' + CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) = 1 THEN '' '' ELSE '','' END + ''(''+ ' + @Actual_Values + '+'')''' + ' ' + 
 COALESCE(@from,' FROM ' + @Source_Table_Qualified + ' (NOLOCK) ORDER BY ' + @PK_column_list)

 SET @output = CASE WHEN ISNULL(@results_to_text, 1) = 1 THEN '' ELSE '---' END


--Determining whether to ouput any debug information
IF @debug_mode =1
 BEGIN
 SET @output += @b + '/*****START OF DEBUG INFORMATION*****'
 SET @output += @b + ''
 SET @output += @b + 'The primary key column list:'
 SET @output += @b + @PK_column_list
 SET @output += @b + ''
 SET @output += @b + 'The INSERT column list:'
 SET @output += @b + @Column_List
 SET @output += @b + ''
 SET @output += @b + 'The UPDATE column list:'
 SET @output += @b + @Column_List_For_Update
 SET @output += @b + ''
 SET @output += @b + 'The SELECT statement executed to generate the MERGE:'
 SET @output += @b + @Actual_Values
 SET @output += @b + ''
 SET @output += @b + '*****END OF DEBUG INFORMATION*****/'
 SET @output += @b + ''
 END
 
IF (@include_use_db = 1)
 BEGIN
	SET @output += @b 
	SET @output += @b + 'USE [' + DB_NAME() + ']'
	SET @output += @b + ISNULL(@batch_separator, '')
	SET @output += @b 
 END

IF (@nologo = 0)
 BEGIN
 SET @output += @b + '--MERGE generated by ''sp_generate_merge'' stored procedure'
 SET @output += @b + '--Originally by Vyas (http://vyaskn.tripod.com/code): sp_generate_inserts (build 22)'
 SET @output += @b + '--Adapted for SQL Server 2008+ by Daniel Nolan (https://twitter.com/dnlnln)'
 SET @output += @b + ''
 END

IF (@include_rowsaffected = 1) -- If the caller has elected not to include the "rows affected" section, let MERGE output the row count as it is executed.
 SET @output += @b + 'SET NOCOUNT ON'
 SET @output += @b + ''


--Determining whether to print IDENTITY_INSERT or not
IF (LEN(@IDN) <> 0)
 BEGIN
 SET @output += @b + 'SET IDENTITY_INSERT ' + @Target_Table_For_Output + ' ON'
 SET @output += @b + ''
 END


--Temporarily disable constraints on the target table
DECLARE @output_enable_constraints NVARCHAR(MAX) = ''
DECLARE @ignore_disable_constraints BIT = IIF((OBJECT_ID(@Source_Table_Qualified, 'U') IS NULL), 1, 0)
IF @disable_constraints = 1 AND @ignore_disable_constraints = 1
BEGIN
	PRINT 'Warning: @disable_constraints=1 will be ignored as the source table does not exist'
END
ELSE IF @disable_constraints = 1
BEGIN
	DECLARE @Source_Table_Constraints TABLE ([name] SYSNAME PRIMARY KEY, [is_not_trusted] bit, [is_disabled] bit)
	INSERT INTO @Source_Table_Constraints ([name], [is_not_trusted], [is_disabled])
	SELECT [name], [is_not_trusted], [is_disabled] FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID(@Source_Table_Qualified, 'U')
	UNION
	SELECT [name], [is_not_trusted], [is_disabled] FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(@Source_Table_Qualified, 'U')

	DECLARE @Constraint_Ct INT = (SELECT COUNT(1) FROM @Source_Table_Constraints)
	IF @Constraint_Ct = 0
	BEGIN
		PRINT 'Warning: @disable_constraints=1 will be ignored as there are no foreign key or check constraints on the source table'
		SET @ignore_disable_constraints = 1
	END
	ELSE IF ((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_disabled] = 1) = (SELECT COUNT(1) FROM @Source_Table_Constraints))
	BEGIN
		PRINT 'Warning: @disable_constraints=1 will be ignored as all foreign key and/or check constraints on the source table are currently disabled'
		SET @ignore_disable_constraints = 1
	END
	ELSE
	BEGIN
		DECLARE @All_Constraints_Enabled BIT = IIF((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_disabled] = 0) = @Constraint_Ct, 1, 0)
		DECLARE @All_Constraints_Trusted BIT = IIF((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_not_trusted] = 0) = @Constraint_Ct, 1, 0)
		DECLARE @All_Constraints_NotTrusted BIT = IIF((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_not_trusted] = 1) = @Constraint_Ct, 1, 0)

		IF @All_Constraints_Enabled = 1 AND @All_Constraints_Trusted = 1
		BEGIN
			SET @output += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' NOCHECK CONSTRAINT ALL' -- Disable constraints temporarily
			SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' WITH CHECK CHECK CONSTRAINT ALL' -- Enable the previously disabled constraints and re-check all data
		END
		ELSE IF @All_Constraints_Enabled = 1 AND @All_Constraints_NotTrusted = 1
		BEGIN
			SET @output += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' NOCHECK CONSTRAINT ALL' -- Disable constraints temporarily
			SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' CHECK CONSTRAINT ALL' -- Enable the previously disabled constraints, but don't re-check data 
		END
		ELSE
		BEGIN
			-- Selectively enable/disable constraints, with/without WITH CHECK, on a case-by-case basis
			WHILE ((SELECT COUNT(1) FROM @Source_Table_Constraints) != 0)
			BEGIN
				DECLARE @Constraint_Item_Name SYSNAME = (SELECT TOP 1 [name] FROM @Source_Table_Constraints)
				DECLARE @Constraint_Item_IsDisabled BIT = (SELECT TOP 1 [is_disabled] FROM @Source_Table_Constraints)
				DECLARE @Constraint_Item_IsNotTrusted BIT = (SELECT TOP 1 [is_not_trusted] FROM @Source_Table_Constraints)

				IF (@Constraint_Item_IsDisabled = 1)
				BEGIN
					DELETE FROM @Source_Table_Constraints WHERE [name] = @Constraint_Item_Name -- Don't enable this previously-disabled constraint
					CONTINUE;
				END

				SET @output += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' NOCHECK CONSTRAINT ' + QUOTENAME(@Constraint_Item_Name)
				IF (@Constraint_Item_IsNotTrusted = 1)
				BEGIN
					SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' CHECK CONSTRAINT ' + QUOTENAME(@Constraint_Item_Name) -- Enable the previously disabled constraint, but don't re-check data 
				END
				ELSE
				BEGIN
					SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(@Constraint_Item_Name) -- Enable the previously disabled constraint and re-check all data
				END

				DELETE FROM @Source_Table_Constraints WHERE [name] = @Constraint_Item_Name
			END
		END
	END
END


--Output the start of the MERGE statement, qualifying with the schema name only if the caller explicitly specified it
SET @output += @b + 'MERGE INTO ' + @Target_Table_For_Output + ' AS [Target]'

IF @include_values = 1
BEGIN
 SET @output += @b + 'USING ('
 --All the hard work pays off here!!! You'll get your MERGE statement, when the next line executes!
 DECLARE @tab TABLE (ID INT NOT NULL PRIMARY KEY IDENTITY(1,1), val NVARCHAR(max));
 INSERT INTO @tab (val)
 EXEC (@Actual_Values)

 IF (SELECT COUNT(*) FROM @tab) <> 0 -- Ensure that rows were returned, otherwise the MERGE statement will get nullified.
 BEGIN
  SET @output += 'VALUES' + CAST((SELECT @b + val FROM @tab ORDER BY ID FOR XML PATH('')) AS XML).value('.', 'NVARCHAR(MAX)');
 END
 ELSE
 BEGIN
  -- Mimic an empty result set by returning zero rows from the target table
  SET @output += 'SELECT ' + @Column_List + ' FROM ' + @Target_Table_For_Output + ' WHERE 1 = 0 -- Empty dataset (source table contained no rows at time of MERGE generation) '
 END

 --Output the columns to correspond with each of the values above--------------------
 SET @output += @b + ') AS [Source] (' + @Column_List + ')'
END
ELSE
 IF @hash_compare_column IS NULL
 BEGIN
  SET @output += @b + 'USING ' + @Source_Table_For_Output + ' AS [Source]';
 END
 ELSE
 BEGIN
  SET @output += @b + 'USING (SELECT ' + @Column_List + ', HASHBYTES(''SHA2_256'', CONCAT(' + REPLACE(@Column_List,'],[','],''|'',[') +')) AS [' + @hash_compare_column  + '] FROM ' + @Source_Table_For_Output + ') AS [Source]'
 END

--Output the join columns ----------------------------------------------------------
SET @output += @b + 'ON (' + @PK_column_joins + ')'


--When matched, perform an UPDATE on any metadata columns only (ie. not on PK)------
IF LEN(@Column_List_For_Update) <> 0
BEGIN
 --Adding column @hash_compare_column to @ColumnList and @Column_List_For_Update if @hash_compare_column is not null
 IF @update_only_if_changed = 1 AND @hash_compare_column IS NOT NULL AND @SourceHashColumn = 0
 BEGIN
	SET @Column_List_For_Update = @Column_List_For_Update + ',' + @b + '  [Target].[' + @hash_compare_column +'] = [Source].[' + @hash_compare_column +']'
	SET @Column_List = @Column_List + ',[' + @hash_compare_column + ']'
 END
 SET @output += @b + 'WHEN MATCHED ' + 
	 CASE WHEN @update_only_if_changed = 1 AND @hash_compare_column IS NOT NULL
	 THEN 'AND ([Target].[' + @hash_compare_column +'] <> [Source].[' + @hash_compare_column +'] OR [Target].[' + @hash_compare_column + '] IS NULL) ' 
	 ELSE CASE WHEN @update_only_if_changed = 1 AND @hash_compare_column IS NULL THEN
	 'AND (' + @Column_List_For_Check + ') ' ELSE '' END END + 'THEN'
 SET @output += @b + ' UPDATE SET'
 SET @output += @b + '  ' + LTRIM(@Column_List_For_Update)
END


--When NOT matched by target, perform an INSERT------------------------------------
SET @output += @b + 'WHEN NOT MATCHED BY TARGET THEN';
SET @output += @b + ' INSERT(' + @Column_List + ')'
SET @output += @b + ' VALUES(' + REPLACE(@Column_List, '[', '[Source].[') + ')'


--When NOT matched by source, DELETE the row as required
IF @delete_if_not_matched=1 
BEGIN
 SET @output += @b + 'WHEN NOT MATCHED BY SOURCE THEN '
 SET @output += @b + ' DELETE;'
END
ELSE
BEGIN
 SET @output += ';'
END;
SET @output += @b 


--Display the number of affected rows to the user, or report if an error occurred---
IF @include_rowsaffected = 1
BEGIN
 SET @output += @b + 'DECLARE @mergeError int'
 SET @output += @b + ' , @mergeCount int'
 SET @output += @b + 'SELECT @mergeError = @@ERROR, @mergeCount = @@ROWCOUNT'
 SET @output += @b + 'IF @mergeError != 0'
 SET @output += @b + ' BEGIN'
 SET @output += @b + ' PRINT ''ERROR OCCURRED IN MERGE FOR ' + @Target_Table_For_Output + '. Rows affected: '' + CAST(@mergeCount AS VARCHAR(100)); -- SQL should always return zero rows affected';
 SET @output += @b + ' END'
 SET @output += @b + 'ELSE'
 SET @output += @b + ' BEGIN'
 SET @output += @b + ' PRINT ''' + @Target_Table_For_Output + ' rows affected by MERGE: '' + CAST(@mergeCount AS VARCHAR(100));';
 SET @output += @b + ' END'
 SET @output += @b + ISNULL(@batch_separator, '')
 SET @output += @b + @b
END

--Re-enable the temporarily disabled constraints-------------------------------------
IF @disable_constraints = 1 AND @ignore_disable_constraints = 0
BEGIN
	SET @output += @output_enable_constraints
	SET @output += @b + ISNULL(@batch_separator, '')
	SET @output += @b
END


--Switch-off identity inserting------------------------------------------------------
IF (LEN(@IDN) <> 0)
 BEGIN
 SET @output += @b
 SET @output += @b +'SET IDENTITY_INSERT ' + @Target_Table_For_Output + ' OFF'
 	
 END

IF (@include_rowsaffected = 1)
BEGIN
 SET @output += @b
 SET @output +=      'SET NOCOUNT OFF'
 SET @output += @b + ISNULL(@batch_separator, '')
 SET @output += @b
END

SET @output += @b + ''
SET @output += @b + ''

IF @results_to_text = 1
BEGIN
	--output the statement to the Grid/Messages tab
	SELECT @output;
END
ELSE IF @results_to_text = 0
BEGIN
	--output the statement as xml (to overcome SSMS 4000/8000 char limitation)
	SELECT [processing-instruction(x)]=@output FOR XML PATH(''),TYPE;
	PRINT 'MERGE statement has been wrapped in an XML fragment and output successfully.'
	PRINT 'Ensure you have Results to Grid enabled and then click the hyperlink to copy the statement within the fragment.'
	PRINT ''
	PRINT 'If you would prefer to have results output directly (without XML) specify @results_to_text = 1, however please'
	PRINT 'note that the results may be truncated by your SQL client to 4000 nchars.'
END
ELSE
BEGIN
	PRINT 'MERGE statement generated successfully (refer to @output OUTPUT parameter for generated T-SQL).'
END

SET NOCOUNT OFF
RETURN 0 --Success. We are done!
END

GO

PRINT 'Created the procedure'
GO


--Mark the proc as a system object to allow it to be called transparently from other databases
EXEC sp_MS_marksystemobject sp_generate_merge
GO

PRINT 'Granting EXECUTE permission on sp_generate_merge to all users'
GRANT EXEC ON sp_generate_merge TO public

SET NOCOUNT OFF
GO

PRINT 'Done'
