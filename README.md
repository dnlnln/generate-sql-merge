Generate SQL MERGE statements with Table data
=============================================

This stored procedure produces a MERGE statement for a given table. The produced MERGE uses a multi-row VALUES clause containing all the source table data, matching existing data in the target (ie. destination table) by including table-join logic based on primary key information in the system catalog.

It was adapted for SQL Server 2008 from Vyas' INSERT generation proc, originally written for SQL Server 2000 (see acknowledgements below).


## How Does it Work?
The generated MERGE statement populates the target table to match the source data. This includes the removal of any excess rows that are not present in the source.

When the generated MERGE statement is executed, the following logic is applied based on whether a match is found:

- If the source row does not exist in the target table, an INSERT is performed
- If a given row in the target table does not exist in the source, a DELETE is performed
- If the source row already exists in the target table and has changed, an UPDATE is performed
- If the source row already exists in the target table but the data has not changed, no action is performed (configurable)


## Use Cases
- Generate statements for static data tables, store the .SQL file in source control/add it to a Visual Studio Database Project and use it as part of your Dev/Test/Prod deployments. The generated statements are re-runnable, so you can make changes to the file and easily migrate those changes between environments. 
- Generate statements from your Production tables and then run those statements in your Dev/Test environments. Schedule this as part of a SQL Job to keep all of your environments in-sync. 
- Enter test data into your Dev environment, and then generate statements from the Dev tables so that you can always reproduce your test database with valid sample data.


## Acknowledgements
This procedure was adapted from "sp_generate_inserts", written by Narayana Vyas Kondreddi (http://vyaskn.tripod.com). I made a number of attempts to get in touch with Vyas but unfortunately have not been able to reach him. No copyright infringement is intended and I will of course respect his wishes if asks for this to be removed.

I would also like to acknowledge:

- Bill Graziano -- Blog post that provided the groundwork for MERGE statement generation
 (http://weblogs.sqlteam.com/billg/archive/2011/02/15/generate-merge-statements-from-a-table.aspx)
- Bill Gibson  -- Blog post that detailed the static data table use case; the inspiration for this proc
 (http://blogs.msdn.com/b/ssdt/archive/2012/02/02/including-data-in-an-sql-server-database-project.aspx)
- Nathan Skerl -- Provided a novel way of working around the 8000 character limit in SSMS
 (http://stackoverflow.com/a/10489767/266882)
 
 
## Installation
Simply execute the script, which will install it in `[master]` database as a system procedure (making it executable within user databases).


## Known Limitations
This procedure has explicit support for the following datatypes: (small)datetime(2), (n)varchar, (n)text, (n)char, int, float, real, (small)money, timestamp, rowversion, uniqueidentifier and (var)binary. All others are implicitly converted to their CHAR representations so YMMV depending on the datatype. Additionally, this procedure has not been extensively tested with UNICODE datatypes.

The Image datatype is not supported and an error will be thrown if these are not excluded using the @cols_to_exclude parameter.


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