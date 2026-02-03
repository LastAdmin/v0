$SampleSizeLabel = New-Label
$SampleSizeLabel.Location = Location 15 115
$SampleSizeLabel.Size = Size 120 20
$SampleSizeLabel.Text = "Sample Size"
$SampleSizeLabel.ForeColor = Color 255 255 255

$SampleSize = New-NumericUpDown
$sampleSize.Location = Location 15 135
$SampleSize.Size = Size 120 20
$SampleSize.Minimum = 100
$SampleSize.Maximum = 100000000
$SampleSize.Value = 1000
$SampleSize.ThousandsSeparator = $true
$SampleSize.BackColor = Color 100 100 100
$SampleSize.ForeColor = Color 255 255 255

$LeftPanel.Controls.Add($SampleSizeLabel)
$LeftPanel.Controls.Add($SampleSize)