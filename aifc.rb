#!/usr/bin/ruby
# Alexandre Pierret
require 'find'
require 'zlib'
require 'sqlite3'
require 'time'


now = Time.new.to_i #used to set date as a seqence_id in SQLite database

def putsDebug(msg)
	puts msg
end

def putsArrayDebug(array)
	array.each do |line|
		puts line.map { |field| field }.join(" ")
	end
end

# Return the CRC32 checksum of a file
def getFileCRC(filename)
	begin
		openfile = File.open(filename, 'rb') do | openfile |
			filecontent = openfile.read
			filecrc = Zlib.crc32(filecontent,0).to_s(16).upcase
			#puts "Filename : #{filename} | CRC #{filecrc}"
			return filecrc
		end
	rescue
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
changeArray = Array.new #Initialize Array of changed entry

begin
	db = SQLite3::Database.open "aifc.db" #Open or create SQLite database
	putsDebug "SQLite version: #{db.get_first_value('SELECT SQLITE_VERSION()')}" #Debug: print SQLite version
	db.execute("CREATE TABLE IF NOT EXISTS files(filename TEXT, crc TEXT, time INTEGER)") #Create table if not already exist

	Find.find(ARGV[0]) do | filename | #Do a find from a path
		if File::file?(filename) #If file found is a regular file
		then
			newFileCRC = getFileCRC(filename) #Get the local CRC
			putsDebug("Regular local file found. Filename : #{filename} | CRC #{newFileCRC}") #Debug: print local file information
			oldFileCRC = getDatabaseFileCRC(db, filename)
			if oldFileCRC #Check if a CRC has been returned from DB
			then #yes, it means file is already present in database
				if newFileCRC == oldFileCRC
				then #No change since last scan
					putsDebug("No change since last time. Updating scanTime in database")
					db.execute("UPDATE files SET time=#{now} WHERE filename='#{filename}'") #Update entry scanTime
				else #File has changed since last time
					putsDebug("Change since last time. Adding file to changeArray and updating CRC and scanTime in database")
					changeArray.push([filename,oldFileCRC,newFileCRC]) #Add file to file change
					db.execute("UPDATE files SET crc='#{newFileCRC}', time=#{now} WHERE filename='#{filename}'") #Update entry CRC and scanTime
				end
			else #no, it's a new file
				putsDebug("New file. Adding file to newArray and adding CRC and scanTime to database")
				newArray.push([filename,newFileCRC])
				db.execute("INSERT INTO files(filename, crc, time) VALUES ('#{filename}','#{newFileCRC}',#{now})") #Create entry
			end
		end
	end
rescue SQLite3::Exception => e
	puts "Exception occured in Main()"
	puts e
ensure
	db.close if db
end

# Get filename and clean all deleted files in dabatase
### todo


# Report
putsDebug("New entry:")
putsArrayDebug(newArray)

putsDebug("Changed entry:")
putsArrayDebug(changeArray)



exit()
