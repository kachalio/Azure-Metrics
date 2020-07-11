# Need to have this Az installed
# Install-Module -Name Az -AllowClobber
# https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.1.0

$StartTime = Get-Date

function Create-DataTable {
    Param
    (
        [Object[]] $dataTableSpecification
    )
  
    $dataTable = New-Object Data.dataTable;
  
    foreach ($col in $dataTableSpecification) {
        $column = New-Object Data.DataColumn;
        $column.DataType = $col.Type;
        $column.ColumnName = $col.Name;
        $dataTable.Columns.Add($column);
    }
  
    return , $dataTable #This makes it return as an array...which works but just returning will return null. Likely a reference vs value issue.
}

Write-Host $psISE.CurrentFile.FullPath
Write-Host $PSScriptRoot

$ResourceUsage_Specification = @();
$ResourceUsage_Specification += [PSCustomObject] @{Name = 'Resource'; Type = [string] }
$ResourceUsage_Specification += [PSCustomObject] @{Name = 'Metric'; Type = [string] }
$ResourceUsage_Specification += [PSCustomObject] @{Name = 'Aggregation'; Type = [string] }
$ResourceUsage_Specification += [PSCustomObject] @{Name = 'Value'; Type = [int] }
$ResourceUsage_Specification += [PSCustomObject] @{Name = 'Timestamp'; Type = [datetime] }
$ResourceUsage_datatable = Create-DataTable -dataTableSpecification $ResourceUsage_Specification


### Defining some Variables.
#  these choose the metrics, and aggregations you want to pull from Azure
$Metrics = 'Percentage CPU', 'Disk Read Operations/Sec', 'Disk Write Operations/Sec'
$Aggregations = 'Maximum', 'Minimum'

# files
$outputFilename = "VMList" + $((Get-Date).ToString('MM-dd-yyyy_hh-mm-ss'))
$inputPath = $PSScriptRoot + '\VMList.txt'
$VMs = Get-Content -Path $inputPath

# Database Connection
$dbConnection = New-Object System.Data.SqlClient.SqlConnection
$dbConnection.ConnectionString = ""
$cmd = New-Object System.Data.SqlClient.SqlCommand
$dbConnection.Open()
$cmd.connection = $dbConnection



# Let's get it going!
$i = 0
#$Credential = Get-Credential
#Connect-AzureRmAccount -Credential $Credential
$ResourceUsage_datatable.Clear()
foreach ($VM in $VMs) {
    # Some stuff to show progress
    $i++
    $percentComplete = [math]::Round(($i / $VMs.Count) * 100,0)
    Write-Progress -Activity "metrics for $($Vm)" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
    foreach ($Metric in $Metrics){
        foreach ($Aggregation in $Aggregations) {

            $AverageCPURecords = Get-AzMetric -AggregationType $Aggregation -MetricName $Metric -WarningAction SilentlyContinue -ResourceId $VM -TimeGrain 01:00:00 -StartTime $StartTime.AddDays(-30) -EndTime $StartTime.AddMinutes(-1) 

            foreach ($AverageCPURecord in $AverageCPURecords.Data) {
            
                $row_ResourceUsage_datatable = $ResourceUsage_datatable.NewRow()
                $row_ResourceUsage_datatable.Resource = $VM
                $row_ResourceUsage_datatable.Metric = $Metric
                if ([string]::IsNullOrEmpty($AverageCPURecord.$Aggregation)) {
                    $row_ResourceUsage_datatable.Value = 0
                }
                else {
                    $row_ResourceUsage_datatable.Value = $AverageCPURecord.$Aggregation
                }
                $row_ResourceUsage_datatable.Aggregation = $Aggregation
                $row_ResourceUsage_datatable.Timestamp = $AverageCPURecord.Timestamp
                $ResourceUsage_datatable.Rows.Add($row_ResourceUsage_datatable)

                
                #Inserts information to the DB
                $cmd.CommandText = "INSERT INTO AzureUsageMetrics (Resource, Metric, Aggregation, Value, Timestamp) VALUES('{0}','{1}','{2}','{3}','{4}'); " -f $row_ResourceUsage_datatable.Resource, $row_ResourceUsage_datatable.Metric, $row_ResourceUsage_datatable.Aggregation, $row_ResourceUsage_datatable.Value, $row_ResourceUsage_datatable.Timestamp
                $result = $cmd.ExecuteNonQuery();
            
            }
        }
    }
}

#Closes Connection
$dbconnection.Close()

# $ResourceUsage_datatable | export-csv -Path "$env:USERPROFILE\Desktop\$outputFilename.csv" -NoTypeInformation
$endtime = get-date
$Time = New-TimeSpan -Start $StartTime -End $endtime
write-host $time.TotalMinutes " Minutes to complete"