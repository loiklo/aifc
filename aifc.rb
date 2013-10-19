#!/usr/bin/ruby
# Alexandre Pierret
require 'find'
require 'zlib' #for CRC
require 'sqlite3'
require 'time'
require 'optparse' #options parsing


# OptionParser Array
$options = {}
optparse = OptionParser.new do|opts|
	# Top of the help screen
	opts.banner = "Usage: aifc.rb [options] path1 path2 ..."
	# Options
	$options[:debug] = false
	opts.on( '-d', '--debug', 'Output debug information' ) do
		$options[:debug] = true
	end
	$options[:reset] = false
	opts.on( '-r', '--reset', 'Reset database before scan' ) do
		$options[:reset] = true
	end
	$options[:verbose] = false
	opts.on( '-v', '--verbose', 'Verbose report' ) do
		$options[:reset] = true
	end
	$options[:database] = "aifc.db"
	opts.on( '-b', '--database FILE', 'Use specified database' ) do |file|
		$options[:database] = file
	end
	# Displays the help screen
	opts.on( '-h', '--help', 'Display this screen' ) do
		puts opts
		exit
	end
end
optparse.parse!

now = Time.new.to_i #used to set date as a seqence_id in SQLite database

def putsDebug(msg)
	puts msg if $options[:debug]
end

def putsArrayDebug(array)
	p array if $options[:debug]
end

# Return the CRC32 checksum of a file
def getFileCRC(filename)
	begin
		openfile = File.open(filename, 'rb') do | openfile |
			filecontent = openfile.read
			filecrc = Zlib.crc32(filecontent,0).to_s(16).upcase
			return filecrc
		end
	rescue Exception => e
		puts "Exception occured in checkFileCRC()"
		puts e
		return nil
	ensure
	end
end

# Return CRC stored in database of a file
def getDatabaseFileCRC(db, filename)
	if rs = db.get_first_row("SELECT crc FROM files WHERE filename='#{filename}'")
	then
		putsDebug "getDatabaseFileCRC : Entry #{filename} present in database. CRC is #{rs[0]}"
		return rs[0] #crc
	else
		putsDebug "getDatabaseFileCRC : Entry #{filename} not present in database"
		return nil
	end
end

#Main()
newArray = Array.new #Initialize Array of new entry
changedArray = Array.new #Initialize Array of changed entry
deletedArray = Array.new #Initialize Array of deleted entry
filecount = 0 #Initialize file scan counter

begin
	db = SQLite3::Database.open $options[:database] #Open or create SQLite database
	putsDebug "SQLite version: #{db.get_first_value('SELECT SQLITE_VERSION()')}" #Debug: print SQLite version
	db.execute("CREATE TABLE IF NOT EXISTS files(filename TEXT, crc TEXT, time INTEGER)") #Create table if not already exist
	db.execute("DELETE FROM files") if $options[:reset] #Truncate table if --reset option is specified
	putsDebug("Row count in databse : #{db.get_first_value("SELECT count(*) FROM files")}")

	# Dump database in memory
	crcTable = Hash.new
	db.execute("SELECT filename, crc, time FROM files").each do | rows |
		crcTable[rows[0]]=[rows[1],rows[2]]
	end
	putsDebug("crcTable.size = #{crcTable.size}")

	ARGV.each do | path |
		Find.find(path) do | filename | #Do a find from a path
			if File::file?(filename) #If file found is a regular file
			then
				filecount+=1
				newFileCRC = getFileCRC(filename) #Get the local CRC
				putsDebug("Regular local file found. Filename : #{filename} | CRC #{newFileCRC}") #Debug: print local file information
#				oldFileCRC = getDatabaseFileCRC(db, filename)
				oldFileCRC = crcTable[filename]
				if oldFileCRC #Check if a CRC has been returned from DB
				then #yes, it means file is already present in database
					if newFileCRC == oldFileCRC
					then #No change since last scan
						putsDebug("No change since last time. Updating scanTime in database")
						db.execute("UPDATE files SET time=#{now} WHERE filename='#{filename}'") #Update entry scanTime
					else #File has changed since last time
						putsDebug("Change since last time. Adding file to changedArray and updating CRC and scanTime in database")
						changedArray.push([filename,oldFileCRC,newFileCRC]) #Add file to file change
						db.execute("UPDATE files SET crc='#{newFileCRC}', time=#{now} WHERE filename='#{filename}'") #Update entry CRC and scanTime
					end
				else #no, it's a new file
					putsDebug("New file. Adding file to newArray and adding CRC and scanTime to database")
					newArray.push([filename,newFileCRC])
				end
			end
		end
	end
	
	
	
	
	# Insert in DB per bloc of #{insertPerIteration} entry
	insertPerIteration = 500
	if newArray.size != 0
		insertIteration = (newArray.size / insertPerIteration).to_i
		putsDebug("insertIteration = #{insertIteration}")
		(0..insertIteration).each do | i |
			dbInsert = "INSERT INTO files(filename, crc, time) VALUES "
			lineStart = i*insertPerIteration
			lineStop = [(i+1)*insertPerIteration-1, newArray.size-1].min
			putsDebug("lineStart = #{lineStart}")
			putsDebug("lineStop = #{lineStop}")
			(lineStart..lineStop).each do | j |
				dbInsert += "('#{newArray[j][0]}','#{newArray[j][1]}',#{now}),"
			end
			db.execute dbInsert.chop #chop: remove the last ","
		end
	end

	# DB Cleaning
	if rsCleanedFile = db.execute("SELECT filename FROM files WHERE time!='#{now}'") #Select all entry in DB not updated this time
	then
		rsCleanedFile.each do | cleanedFile |
			deletedArray.push(cleanedFile[0]) #Add all entry to the deleted file array
		end
		db.execute("DELETE FROM files WHERE time!='#{now}'") #Delete all not updated entry
	end
rescue SQLite3::Exception => e
	puts "Exception occured in Main()"
	puts e
ensure
	db.close if db
end

putsDebug("New entry:")
#putsArrayDebug(newArray)
putsDebug("Changed entry:")
putsArrayDebug(changedArray)
putsDebug("Deleted entry:")
putsArrayDebug(deletedArray)

# Report
report="Summary\n"
report+="=======\n"
report+="Scanned file(s) :\t#{filecount}\n"
report+="New file(s) :\t\t#{newArray.size}\n"
report+="Modified file(s) :\t#{changedArray.size}\n"
report+="Deleted file(s) :\t#{deletedArray.size}\n"
if changedArray.size != 0
then
	report+="\n"
	report+="Detail of modified file(s)\n"
	report+="==========================\n"
	report+="| Old CRC  | New CRC  | Filename ...\n"
	report+="|----------|----------|-------------\n"
	changedArray.each do | line |
		report+="| #{line[1]} | #{line[2]} | #{line[0]}\n"
	end
end
if deletedArray.size != 0
then
	report+="\n"
	report+="Detail of deleted file(s)\n"
	report+="=========================\n"
	report+="| Filename ...\n"
	report+="|-------------\n"
	deletedArray.each do | line |
		report+="| #{line}\n"
	end
end

puts report

exit 0
