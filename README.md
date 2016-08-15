Generate SQL MERGE statements with Table data
=============================================

This system stored procedure takes a table name as a parameter and generates a `MERGE` statement containing all the table data. 

This is useful if you need to [migrate static data between databases](http://support.ready-roll.com/customer/portal/articles/437299-including-static-data-in-db-deployments), eg. the generated MERGE statement can be included in source control and used to deploy data between DEV/TEST/PROD.

The stored procedure itself is installed within the `[master]` database as a system object, allowing the proc to be called within the context of user databases (e.g. `EXEC Northwind.dbo.sp_generate_merge 'Region'`)
(The above is now commented out so that it creates in user database, so example changes to  (e.g. `EXEC dbo.sp_generate_merge 'Region'`))
Key features:

- Include or exclude specific columns from output (eg. exclude DateCreated/DateModified columns)
- Only update the target database when changes in the source data are found
- Support for larger tables (gets around character limitations in some SQL clients)


## How Does it Work?
The generated MERGE statement populates the target table to match the source data. This includes the removal of any excess rows that are not present in the source.

When the generated MERGE statement is executed, the following logic is applied based on whether a match is found:

- If the source row does not exist in the target table, an `INSERT` is performed
- If a given row in the target table does not exist in the source, a `DELETE` is performed (causing huge slowness)
- If the source row already exists in the target table and has changed, an `UPDATE` is performed
- If the source row already exists in the target table but the data has not changed, no action is performed (configurable)


## Use Cases
- Generate statements for static data tables, store the .SQL file in source control/add it to a Visual Studio Database Project and use it as part of your Dev/Test/Prod deployments. The generated statements are re-runnable, so you can make changes to the file and easily migrate those changes between environments. 
- Generate statements from your Production tables and then run those statements in your Dev/Test environments. Schedule this as part of a SQL Job to keep all of your environments in-sync. 
- Enter test data into your Dev environment, and then generate statements from the Dev tables so that you can always reproduce your test database with valid sample data.


## Acknowledgements
This procedure was adapted from **sp\_generate\_inserts**, written by Narayana Vyas Kondreddi (http://vyaskn.tripod.com). I made a number of attempts to get in touch with Vyas but unfortunately have not been able to reach him. No copyright infringement is intended and I will of course respect his wishes if asks for this to be removed.

I would also like to acknowledge:

- Bill Graziano -- Blog post that provided the groundwork for MERGE statement generation
 (http://weblogs.sqlteam.com/billg/archive/2011/02/15/generate-merge-statements-from-a-table.aspx)
- Bill Gibson  -- Blog post that detailed the static data table use case; the inspiration for this proc
 (http://blogs.msdn.com/b/ssdt/archive/2012/02/02/including-data-in-an-sql-server-database-project.aspx)
- Nathan Skerl -- Provided a novel way of working around the 8000 character limit in SSMS
 (http://stackoverflow.com/a/10489767/266882)
 
 
## Installation
Simply execute the script, which will install it in `[master]` database as a system procedure (making it executable within user databases).
The use master is currently removed from it in case login limitation won't allow creation in master, create in user database works too.

## Known Limitations
This procedure has explicit support for the following datatypes: (small)datetime(2), (n)varchar, (n)text, (n)char, int, float, real, (small)money, timestamp, rowversion, uniqueidentifier and (var)binary. All others are implicitly converted to their CHAR representations so YMMV depending on the datatype. Additionally, this procedure has not been extensively tested with UNICODE datatypes.

The Image datatype is not supported and an error will be thrown if these are not excluded using the `@cols_to_exclude` parameter.


## Usage
1. Ensure that your SQL client is configured to send results to grid.
2. Execute the proc, providing the source table name as a parameter
3. Click the hyperlink within the resultset.
4. Copy the SQL (excluding the Output tags) and paste into a new query window to execute.


## Example
To generate a MERGE statement containing all data within the Person.AddressType table, excluding the ModifiedDate and rowguid columns:

```
EXEC AdventureWorks.dbo.sp_generate_merge @schema = 'Person', @table_name ='AddressType', @cols_to_exclude = '''ModifiedDate'',''rowguid'''
```

###Output

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
## Changes in this fork
1. Commented out using master so it creates on user db instead
2. The query will became really slow with more data invovled and sql server would not even able to run it as all data is forming into a memory table. Therefore a new parameter was introduced @source_as_temp_table which will put those raw data into a tempporary table first and then use that as a source to improve performance
3. Along with @source_as_temp_table @output_identity_into_temp will use OUTPUT keyword to write all matching identity pk back into the temporary table with extra '_Source' appended to the identity column name as a new column, so that when exporting linked record between table when identiy insert is not an option
4. In order to make #3 mapping actually work @script_before_merge @script_after_merge was introduced to ingect sql code for mapping, which also kind of need @drop_temp_table
5. Added @ignore_duplicates_for_update so that when source data for no reason has duplicates except identity rerun the script won't causing trouble with rownumber
6. Added @different_join_columns so that the match can be used on different columns
7. @different_join_nullable_columns is a subset of @different_join_columns to tell those columns might be nullable so that we match them with both null check on source and target

## Example

I want to export one certain set of data from A(Id, Code, Column1, Column2) and B(Id, AId, Data1, Data2), which is a 1-N mapping, when applying on a different DB I would like remain the relationship between them but not using identity insert, based on that in A table there are other columns is unique enough to match the target

```
DECLARE @from_query VARCHAR(max) = 'from A where Id IN (' + @sIdString + ')'
EXEC sp_generate_merge 'A', @include_use_db = 0,  @source_as_temp_table = 1, @ommit_identity = 0, @results_to_text =1,
		@from = @from_query, @delete_if_not_matched = 0, @update_only_if_changed = 0,
		@new_identity_in_temp_table = 1, @different_join_columns = 'Code,',
 		@script_before_merge = '',
		@script_after_merge = '',
		@drop_temp_table = 0, @output_identity_into_temp = 1


SET @from_query = 'from B where Id IN (' + @sBIdString + ')'
EXEC sp_generate_merge 'B', @include_use_db = 0,  @source_as_temp_table = 1, @ommit_identity = 0, @results_to_text =1,
		@from = @from_query, @delete_if_not_matched = 0,  @update_only_if_changed = 0,
		@new_identity_in_temp_table = 1, @different_join_columns = 'AId,Data1,Data2,',
		@different_join_nullable_columns = 'Data2,',
 		@script_before_merge = 'UPDATE T
								SET T.[AId] = T1.[Id]
								FROM  #tempB AS T 
									JOIN #tempA AS T1
										ON T1.[Id_Source] = T.[AId];',
		@script_after_merge = '',
		@drop_temp_table = 0, @output_identity_into_temp = 1, @ignore_duplicates_for_update = 1
```