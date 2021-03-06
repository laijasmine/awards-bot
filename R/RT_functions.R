#' Wrapper function that sends all correspondences
#' 
#' Wrapper function for 'create_ticket_and_send_initial_correspondence',
#' 'send_annual_report_correspondence', 'send_aon_correspondence', and
#' 'send_one_month_remaining_correspondence'
#' 
#' @param awards_db (data.frame) awards database
#' @param database_path (character) the path to save the database to
#' 
#' @importFrom magrittr '%>%' 
send_correspondences <- function(awards_db, database_path) {
  indices <- which(awards_db$active_award_flag == 'yes') 
  db <- awards_db[indices,]
  
  db <- create_ticket_and_send_initial_correspondence(db, database_path) %>%
    send_annual_report_correspondence(., database_path) %>%
    send_aon_correspondence(., database_path) %>%
    send_one_month_remaining_correspondence(., database_path) 
  
  awards_db[indices,] <- db
  
  #send summary of tickets sent
  if(nrow(awards_db[indices,]) > 0) {
    out <- sprintf('I sent %s tickets today', nrow(awards_db[indices,]))	
    slackr::slackr_bot(out)	
  }
  
  return(awards_db)
}

#' Create New Tickets
#' 
#' Run this code to create a new RT ticket based off NSF award number and requestor
#' (PI) email.  Requires a valid RT login in order to run.  
#'
#' @param award (character) NSF award number.
#' @param requestor (character) PI email
#' 
#' @return ticket_id (character) Newly generated RT ticket id
create_ticket <- function(award, requestor) {
  subject <- sprintf('Arctic Data Center NSF Award: %s',  award)
  ticket <- rt::rt_ticket_create(queue = 'arcticAwards',
                                 requestor = requestor,
                                 subject = subject,
                                 rt_base = 'https://support.nceas.ucsb.edu/rt')
  
  #check to see if the object ticket is created successfully
  if(!exists("ticket")) {
    out <- sprintf('I failed to create a ticket for award: %s, from requestor: %s', award, requestor)	
    slackr::slackr_bot(out)	
    return('rt_ticket_create_error')	
  }

  return(ticket)
}


#' Create New Tickets and send initial correspondences 
#' 
#' Run this code to create new RT tickets and send an initial correspondence, based 
#' off a database of new NSF awards.  The database must include: fund_program_name,
#' pi_email, pi_first_name, id (NSF award #), title (NSF award title).  
#'
#' @param awards_db (data.frame) database of NSF awards pulled from NSF-API
#' @param database_path (character) the path to save the database to
#'
#' @return awards_db (data.frame) The initial database with updated RT ticket numbers
create_ticket_and_send_initial_correspondence <- function(awards_db, database_path) {
  # Get awards without an initial correspondence
  indices <- which(is.na(awards_db$contact_initial)) # save indices to re-merge
  db <- awards_db[indices,]
  
  for (i in seq_len(nrow(db))) {
    # Create RT ticket
    db$rt_ticket[i] <- create_ticket(db$id[i], db$pi_email[i])
    
    if (db$rt_ticket[i] == 'rt_ticket_create_error') {
      next 
    }
    # Create correspondence text 
    template <- read_initial_template(db$fund_program_name[i])
    email_text <- sprintf(template,
                          db$pi_first_name[i],
                          db$id[i],
                          db$title[i])
    
    reply <- check_rt_reply(db$rt_ticket[i], email_text)
    
    db$contact_initial[i] <- as.character(Sys.Date())
    
    # re-merge temporary database into permanent
    awards_db[i,] <- db[i,]
    #save the result inbetween
    utils::write.csv(db, file = database_path, row.names = FALSE)
  }
  
  return(awards_db)
}


send_annual_report_correspondence <- function(awards_db, database_path) {
  # Get awards to send annual report correspondence 
  current_date <- as.character(Sys.Date())
  indices <- which(awards_db$contact_annual_report_next == current_date) # save indices to re-merge
  db <- awards_db[indices,]
  
  for (i in seq_len(nrow(db))) {
    # Create correspondence text 
    template <- read_file(file.path(system.file('emails', 'contact_annual_report', package = 'awardsBot')))
    email_text <- sprintf(template,
                          db$pi_first_name[i])
    
    reply <- check_rt_reply(db$rt_ticket[i], email_text)

    # Update last contact date
    db$contact_annual_report_previous[i] <- db$contact_annual_report_next[i]
    
    # re-merge temporary database into permanent
    awards_db[i,] <- db[i, ]
    #save the result inbetween
    utils::write.csv(db, file = database_path, row.names = FALSE)
  }
  
  ## TODO
  # add function that updates annual report correspondence times
  
  
  return(awards_db)
}


send_aon_correspondence <- function(awards_db, database_path){
  current_date <- as.character(Sys.Date())
  indices <- which(awards_db$contact_aon_next == current_date)
  db <- awards_db[indices,]
  
  for (i in seq_len(nrow(db))) {
    # Create correspondence text 
    template <- read_file(file.path(system.file('emails', 'contact_aon_recurring', package = 'awardsBot')))
    email_text <- sprintf(template,
                          db$pi_first_name[i])
    
    reply <- check_rt_reply(db$rt_ticket[i], email_text)
    
    # Update last contact date
    db$contact_aon_previous[i] <- db$contact_aon_next[i]
    
    # re-merge temporary database into permanent
    awards_db[i,] <- db[i, ]
    #save the result inbetween
    utils::write.csv(db, file = database_path, row.names = FALSE)
  }
  
  return(awards_db)
}

  
send_one_month_remaining_correspondence <- function(awards_db, database_path) {
  indices <- which(awards_db$contact_1mo == as.character(Sys.Date()))
  db <- awards_db[indices,]
  
  for (i in seq_len(nrow(db))) {
    # Create correspondence text 
    template <- read_file(file.path(system.file('emails', 'contact_one_month_remaining', package = 'awardsBot')))
    email_text <- sprintf(template,
                          db$pi_first_name[i],
                          db$id[i],
                          db$title[i])
    
    reply <- check_rt_reply(db$rt_ticket[i], email_text)
    
    # Update last contact date
    db$contact_1mo[i] <- as.character(Sys.Date())
    
    # re-merge temporary database into permanent
    awards_db[i,] <- db[i, ]
    #save the result inbetween
    utils::write.csv(db, file = database_path, row.names = FALSE)
  }

  return(awards_db)
}
  

# General function that sends a correspondence based on a specified time
# 
#This function sends a correspondence based on a specified time interval from 
# the startDate or the expDate.  You can specify which direction in time you'd like
# to go based on the starting point, as well as the time interval in years, months,
# and days.  
send_correspondence_at_time_x <- function(awards_db,
                                          starting_point,
                                          direction,
                                          years = 0,
                                          months = 0, 
                                          days = 0,
                                          rtTicket, 
                                          email_text) {
  if (!(starting_point %in% c('start_date', 'exp_date'))) {
    stop('starting point must be one of "start_date" or "exp_date"')
  }
  if (!is.numeric(c(years, months, days))) {
    stop('"years", "months", and "days" arguments must be numeric')
  } 
  
  db <- awards_db
  dates <- as.Date(db[[starting_point]])
  time_int <- lubridate::period(c(days, months, years), c('day', 'month', 'year'))
  dates + time_int
  
}

check_rt_reply <- function(ticket_number, email) {	
  tryCatch({
    ticket <- rt::rt_ticket_history_reply(ticket_id = ticket_number,
                                text = email,
                                rt_base = 'https://support.nceas.ucsb.edu/rt')
  },
  error = function(e) { 
    out <- sprintf('I failed to reply on: %s', ticket)	
    slackr::slackr_bot(out)
  })
  
  return(ticket)
} 

## helper function to read in email templates
read_file <- function(path) {
  suppressWarnings(paste0(readLines(path), collapse = '\n '))
}

## helper function read in general, AON, or SS initial template
read_initial_template <- function(fund_program_name) {
  stopifnot(is.character(fund_program_name))
  
  if (grepl('AON', fund_program_name)) {
    path <- file.path(system.file('emails', 'contact_initial_aon', package = 'awardsBot'))
  } else if (grepl('SOCIAL', fund_program_name)) {
    path <- file.path(system.file('emails', 'contact_initial_social_sciences', package = 'awardsBot'))
  } else {
    path <- file.path(system.file('emails', 'contact_initial_ans', package = 'awardsBot'))
  }
  
  if (!file.exists(path)) {
    slackr::slackr_bot('I failed to read in a contact_initial email template, please check that the file paths used by "awardsBot::read_initial_template" all exist.')
  }
  
  template <- read_file(path)
  return(template)
}


## Helper function to check if RT is logged in 
check_rt_login <- function(rt_base) {
  base_api <- paste(stringr::str_replace(rt_base, '\\/$', ''),
                    'REST', '1.0', sep = '/')
  content <- httr::GET(base_api) %>%
    httr::content()
  
  if (stringr::str_detect(content, 'Credentials required')) {
    return(FALSE)
  } else {
    return(TRUE)
  }
}