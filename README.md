Generate SQL MERGE statements with Table data
=============================================

This system stored procedure takes a table name as a parameter and generates a `MERGE` statement containing all the table data. 

This is useful if you need to migrate static data between databases, eg. the generated MERGE statement can be included in source control and used to deploy data between DEV/TEST/PROD.

The stored procedure itself is installed within the `[master]` database as a system object, allowing the proc to be called within the context of user databases (e.g. `EXEC MyDb..sp_generate_merge 'MyTable'`)

Key features:

- Include or exclude specific columns from output (eg. exclude DateCreated/DateModified columns)
- Only update the target database when changes in the source data are found
- Support for larger tables (gets around character limitations in some SQL clients)


## How Does it Work?
The generated MERGE statement populates the target table to match the source data. This includes the removal of any excess rows that are not present in the source.

When the generated MERGE statement is executed, the following logic is applied based on whether a match is found:

- If the source row does not exist in the target table, an `INSERT` is performed
- If a given row in the target table does not exist in the source, a `DELETE` is performed
- If the source row already exists in the target table and has changed, an `UPDATE` is performed
- If the source row already exists in the target table but the data has not changed, no action is performed (configurable)


## Use Cases
The main use cases for which this tool was created to handle:
- Generate statements for static data tables, store the .SQL file in source control/add it to a Visual Studio Database Project and use it as part of your Dev/Test/Prod deployments. The generated statements are re-runnable, so you can make changes to the file and easily migrate those changes between environments. 
- Generate statements from your Production tables and then run those statements in your Dev/Test environments. Schedule this as part of a SQL Job to keep all of your environments in-sync. 
- Enter test data into your Dev environment, and then generate statements from the Dev tables so that you can always reproduce your test database with valid sample data.


## Installation:
Simply execute `sp_generate_merge.sql` to install the proc.
#### Where is the proc installed?

- **OnPremise editions** (SQL Server Standard/Developer/Express/Enterprise):
  Installs into `master` as a system stored procedure, allowing any authenticated users to execute the proc as if it was installed within every database on the server. Usage:
  ```
  EXEC [AdventureWorks]..[sp_generate_merge] 'AddressType', @Schema='Person'
  ```
- **Cloud editions** (Azure SQL/Managed Instance):
  Installs into the _current database_, given that custom system stored procedures aren't an option in cloud editions. Usage:
  ```
  EXEC [sp_generate_merge] 'AddressType', @Schema='Person'
  ```
#### Alternative installation: Temporary stored procedure
Another option is to install `sp_generate_merge` as a temporary stored procedure. This is useful if the database is read only or you don't have "create object" permission. Usage:

1. Edit `sp_generate_merge.sql`, replacing all occurrences of `sp_generate_merge` with `#sp_generate_merge`
2. Connect to the database that you want to use the proc within i.e. `USE [AdventureWorks]`
3. Execute the script
4. Generate merge statements as follows: `EXEC [#sp_generate_merge] @Schema='Person', @Table_Name='AddressType'`


## Acknowledgements

- **Daniel Nolan** -- Creator/maintainer of sp_generate_merge https://danielnolan.io

- **Narayana Vyas Kondreddi** -- Author of `sp_generate_inserts`**, from which `sp_generate_merge` was originally forked (sp_generate_inserts: Copyright © 2002 Narayana Vyas Kondreddi. All rights reserved.) http://vyaskn.tripod.com/code

- **Bill Gibson** -- Blog that detailed the static data table use case; the inspiration for this proc
 http://blogs.msdn.com/b/ssdt/archive/2012/02/02/including-data-in-an-sql-server-database-project.aspx
 
- **Bill Graziano** -- Blog that provided the groundwork for MERGE statement generation
 http://weblogs.sqlteam.com/billg/archive/2011/02/15/generate-merge-statements-from-a-table.aspx 

- **Christian Lorber** -- Contributed hashvalue-based change detection that enables efficient ETL implementations
 https://twitter.com/chlorber

- **Nathan Skerl** -- StackOverflow answer that provided a workaround for the output truncation problem
 http://stackoverflow.com/a/10489767/266882

- **Eitan Blumin** -- Added the ability to divide merges into multiple batches of x rows
 https://www.eitanblumin.com/

**This procedure was adapted from `sp_generate_inserts`, written by [Narayana Vyas Kondreddi](http://vyaskn.tripod.com). I made a number of attempts to get in touch with Vyas to get his blessing for this fork -- given that no license details are specified in his code -- but was unfortunately unable to reach him. No copyright infringement is intended.


## Known Limitations
This procedure has explicit support for the following datatypes: (small)datetime(2), datetimeoffset, (n)varchar, (n)text, (n)char, xml, int, float, real, (small)money, timestamp, rowversion, uniqueidentifier, (var)binary, hierarchyid, geometry and geography. All others are implicitly converted to their CHAR representations so YMMV depending on the datatype.

The deprecated `image` datatype is not supported and an error will be thrown if these are not excluded using the `@cols_to_exclude` parameter.

When using the `@hash_compare_column` parameter, all columns in the source and target table must be implicitly convertible to strings (due to the use of `CONCAT` in the proc to calculate the hash value). This means that the following data types are not supported with `@hash_compare_column`: xml, hierarchyid, image, geometry and geography.


## Usage
1. Install the proc (see _Installation_, above)
2. If using SSMS, ensure that it is configured to send results to grid rather than text.
3. Execute the proc e.g. `EXEC [sp_generate_merge] 'MyTable'`
4. Open the result set (eg. in SSMS/ADO/VSCode, click the hyperlink in the grid)
5. Copy the SQL portion of the text and paste into a new query window to execute.


## Example
To generate a MERGE statement containing all data within the `[Person].[AddressType]` table, excluding the `ModifiedDate` and `rowguid` columns:

```
EXEC AdventureWorks..sp_generate_merge 
  @schema = 'Person', 
  @table_name ='AddressType', 
  @cols_to_exclude = '''ModifiedDate'',''rowguid'''
```

### Output

```
SET NOCOUNT ON
GO 
SET IDENTITY_INSERT [Person].[AddressType] ON
GO
MERGE INTO [Person].[AddressType] AS Target
USING (VALUES
  (1,'Billing')
 ,(2,'Home')
 ,(3,'Main Office')
 ,(4,'Primary')
 ,(5,'Shipping')
 ,(6,'Contact')
) AS Source ([AddressTypeID],[Name])
ON (Target.[AddressTypeID] = Source.[AddressTypeID])
WHEN MATCHED AND (
    NULLIF(Source.[Name], Target.[Name]) IS NOT NULL OR NULLIF(Target.[Name], Source.[Name]) IS NOT NULL) THEN
 UPDATE SET
 [Name] = Source.[Name]
WHEN NOT MATCHED BY TARGET THEN
 INSERT([AddressTypeID],[Name])
 VALUES(Source.[AddressTypeID],Source.[Name])
WHEN NOT MATCHED BY SOURCE THEN 
 DELETE;

SET IDENTITY_INSERT [Person].[AddressType] OFF
GO
SET NOCOUNT OFF
GO
```

## Additional examples

#### Example 1: To generate a MERGE statement for table 'titles':
```
EXEC sp_generate_merge 'titles'
```

#### Example 2: To generate a MERGE statement for 'titlesCopy'  from 'titles' table:
```
EXEC sp_generate_merge 'titles', @schema='titlesCopy'
```

#### Example 3: To generate a MERGE statement for table 'titles' that will unconditionally UPDATE matching rows 
 (ie. not perform a "has data changed?" check prior to going ahead with an UPDATE):
```
EXEC sp_generate_merge 'titles', @update_only_if_changed = 0
```

#### Example 4: To generate a MERGE statement for 'titles' table for only those titles which contain the word 'Computer' in them
Note: Do not complicate the FROM or WHERE clause here. It's assumed that you are good with T-SQL if you are using this parameter
```
EXEC sp_generate_merge 'titles', @from = "from titles where title like '%Computer%' order by title_id"
```

#### Example 5: To print diagnostic info during execution of this proc:
```
EXEC sp_generate_merge 'titles', @debug_mode = 1
```

#### Example 6: If the table is in a different schema to the default eg. `Contact.AddressType`:
```
EXEC sp_generate_merge 'AddressType', @schema = 'Contact'
```

#### Example 7: To generate a MERGE statement for the rest of the columns excluding those of the `image` data type:
```
EXEC sp_generate_merge 'imgtable', @ommit_images = 1
```

#### Example 8: To generate a MERGE statement excluding (omitting) IDENTITY columns:
 (By default IDENTITY columns are included in the MERGE statement)
```
EXEC sp_generate_merge 'mytable', @ommit_identity = 1
```

#### Example 9: To generate a MERGE statement for the TOP 10 rows in the table:
```
EXEC sp_generate_merge 'mytable', @top = 10
```

#### Example 10: To generate a MERGE statement with only those columns you want:
```
EXEC sp_generate_merge 'titles', @cols_to_include = "'title','title_id','au_id'"
```

#### Example 11: To generate a MERGE statement by omitting certain columns:
```
EXEC sp_generate_merge 'titles', @cols_to_exclude = "'title','title_id','au_id'"
```

#### Example 12: To avoid checking the foreign key constraints while loading data with a MERGE statement:
```
EXEC sp_generate_merge 'titles', @disable_constraints = 1
```

#### Example 13: To exclude computed columns from the MERGE statement:
```
EXEC sp_generate_merge 'MyTable', @ommit_computed_cols = 1
```

#### Example 14: To generate a MERGE statement for a table that lacks a primary key:
```
EXEC sp_generate_merge 'StateProvince', @schema = 'Person', @cols_to_join_on = "'StateProvinceCode'"
```

#### Example 15: To generate a statement that MERGEs data directly from the source table to a table in another database:
```
EXEC sp_generate_merge 'StateProvince', @schema = 'Person', @include_values = 0, @target_table = '[OtherDb].[Person].[StateProvince]'
```

#### Example 16: To generate a MERGE statement that will update the target table if the calculated hash value of the source does not match the `Hashvalue` column in the target:
```
EXEC sp_generate_merge
  @schema = 'Person', 
  @target_table = '[Person].[StateProvince]', 
  @table_name = 'v_StateProvince',
  @include_values = 0,   
  @hash_compare_column = 'Hashvalue',
  @include_rowsaffected = 0,
  @nologo = 1,
  @cols_to_join_on = "'ID'"
```

#### Example 17: To generate and immediately execute a MERGE statement that performs an ETL from a table in one database to another:
```
DECLARE @sql NVARCHAR(MAX)
EXEC [AdventureWorks]..sp_generate_merge @output = @sql output, @results_to_text = null, @schema = 'Person', @table_name = 'AddressType', @include_values = 0, @include_use_db = 0, @batch_separator = null, @target_table = '[AdventureWorks_Target].[Person].[AddressType]'
EXEC [AdventureWorks]..sp_executesql @sql
```

#### Example 18: To generate a MERGE that works with a subset of data from the source table only (e.g. will only INSERT/UPDATE rows that meet certain criteria, and not delete unmatched rows):
```
SELECT * INTO #CurrencyRateFiltered FROM AdventureWorks.Sales.CurrencyRate WHERE ToCurrencyCode = 'AUD';
ALTER TABLE #CurrencyRateFiltered ADD CONSTRAINT PK_Sales_CurrencyRate PRIMARY KEY CLUSTERED ( CurrencyRateID )
EXEC tempdb..sp_generate_merge @table_name='#CurrencyRateFiltered', @target_table='[AdventureWorks].[Sales].[CurrencyRate]', @delete_if_not_matched = 0, @include_use_db = 0;
```

#### Example 19: To generate a MERGE split into batches based on a max rowcount per batch:
Note: `@delete_if_not_matched` must be `0`, and `@include_values` must be `1`.
```
EXEC [AdventureWorks]..[sp_generate_merge] @table_name = 'MyTable', @schema = 'dbo', @delete_if_not_matched = 0, @max_rows_per_batch = 100
```