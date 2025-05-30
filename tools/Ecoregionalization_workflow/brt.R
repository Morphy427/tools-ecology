#16/02/2023
## Analyse BRT data

### Clean environment 
rm(list = ls(all.names = TRUE))
options(warn=1)

### load packages

library(dismo, warn.conflicts = FALSE)
library(gbm, warn.conflicts = FALSE)
library(ggplot2, warn.conflicts = FALSE)


#load arguments
args = commandArgs(trailingOnly=TRUE) 
if (length(args)==0)
{
    stop("This tool needs at least one argument")
}else{
    enviro <- args[1]
    species_files <- args[2]
    abio_para <- args[3]
    dec_env <- ifelse(args[8]=="Dot", ".", ",")
    dec_species <- ifelse(args[9]=="Dot", ".", ",")
}

### load data

env = read.table(enviro, dec = dec_env, header = TRUE, sep="\t", na.strings = "-9999")
pred_vars = strsplit(abio_para, ",")[[1]] 
data_files = strsplit(species_files,",")

pred.vars <- character(length(pred_vars))

for (i in seq_along(pred_vars)) {
       pred_var_col <- as.numeric(pred_vars[i])
       pred.vars[i] <- names(env)[pred_var_col]}
       
#environemental parameters
#Carbo,Grav,Maxbearing,Maxmagnit,Meancurmag,Meansal,Meantheta,Mud,Prof,Rugosity,Sand,Seaice_prod,Sili,Slope,Standcurmag,Standsal,Standtheta

#Load functions

make.brt <- function(spe,data,pred.vars,env,nb_file){
   cat(paste("  ", spe,":\n  -> optimising BRT model ",sep=""))
   lr <- 0.05
   no.trees <- 0
   while ( no.trees < 1000 & lr > 0.0005 ) {
    cat(".")
    try(brt_step <- gbm.step(data= data, gbm.x = pred.vars, gbm.y = spe, family = "bernoulli", tree.complexity = 2, learning.rate = lr,max.trees = 10000, plot.main = F))
    # if the gbm does not converge, the return object is null or of size 0
    if (!is.null(brt_step) ) {
      if (object.size(brt_step) > 0 ) {
        no.trees <- brt_step$gbm.call$best.trees
        print(no.trees)
      }
    } else {
      no.trees <- 0
      print(no.trees)
    }

    # decrease the learning rate
    lr <- lr / 2
    print(lr)
  }
   #plot
   if (is.null(brt_step)==FALSE){
     pdf(file = paste("BRT-",spe,".pdf"))
     gbm.plot(brt_step, write.title = T,show.contrib = T, y.label = "fitted function",plot.layout = c(3,3))
     dev.off()
     #total deviance explained as (Leathwick et al., 2006)
     total_deviance <- brt_step$self.statistics$mean.null
     cross_validated_residual_deviance <- brt_step$cv.statistics$deviance.mean
     total_deviance_explained <- (total_deviance - cross_validated_residual_deviance)/total_deviance
     #Validation file
     valid = cbind(spe,brt_step$cv.statistics$discrimination.mean,brt_step$gbm.call$tree.complexity,total_deviance_explained)
     write.table(valid, paste(nb_file,"_brts_validation_ceamarc.tsv",sep=""), quote=FALSE, dec=".",sep="\t" ,row.names=F, col.names=F,append = T)}
   
   return(brt_step)
   }

make.prediction.brt <- function(brt_step){
  #predictions
  preds <- predict.gbm(brt_step,env,n.trees=brt_step$gbm.call$best.trees, type="response")
  preds <- as.data.frame(cbind(env$lat,env$long,preds))
  colnames(preds) <- c("lat","long","Prediction.index")
  #carto
  ggplot()+
    geom_raster(data = preds , aes(x = long, y = lat, fill = Prediction.index))+
    geom_raster(data = preds , aes(x = long, y = lat, alpha = Prediction.index))+
    scale_alpha(range = c(0,1), guide = "none")+
    scale_fill_viridis_c(
      alpha = 1,
      begin = 0,
      end = 1,
      direction = -1,
      option = "D",
      values = NULL,
      space = "Lab",
      na.value = "grey50",
      guide = "colourbar",
      aesthetics = "fill")+
    xlab("Longitude") + ylab("Latitude")+ ggtitle(paste(spe,"Plot of BRT predictions"))+
    theme(plot.title = element_text(size = 10))+
    theme(axis.title.y = element_text(size = 10))+
    theme(axis.title.x = element_text(size = 10))+
    theme(axis.text.y = element_text(size = 10))+
    theme(axis.text.x = element_text(size = 10))+
    theme(legend.text = element_text(size = 10))+
    theme(legend.title = element_text(size = 10))+ 
    coord_quickmap()
  output_directory <- ggsave(paste("BRT-",spe,"_pred_plot.png"))
  
  #Write prediction in a file
  preds <- cbind(preds,spe)
  write.table(preds, paste(nb_file,"_brts_pred_ceamarc.tsv",sep=""), quote=FALSE, dec=".", row.names=F, col.names=!file.exists(paste(nb_file,"_brts_pred_ceamarc.tsv",sep="")),append = T,sep="\t")
}

#### RUN BRT ####
nb_file = 0

# Creating the %!in% operator
`%!in%` <- Negate(`%in%`)

# Data file browsing
for (file in data_files[[1]]) {
  
  # Reading the file
  species_data <- read.table(file, dec = dec_species, sep = "\t", header = TRUE, na.strings = "NA", colClasses = "numeric")
  nb_file = nb_file + 1
 
  # List to store species to predict
  sp = list()
  
  # Selection of columns that are not in 'env' and that are not coordinates or stations
  for (n in names(species_data)) {
    if (n %!in% names(env) && n != 'station' && n != 'decimalLatitude' && n != 'decimalLongitude' && n!='lat' && n!='long'){
       sp = c(sp,n) 
    }
  } 
  # Making predictions for each species 
  for (spe in sp){
   try(make.prediction.brt(make.brt(spe,species_data,pred.vars,env,nb_file)))
   }
}

#Display of abiotic parameters
cat("Here is the list of your abiotic parameters:\n")
cat(paste(pred.vars, collapse = ", "), "\n")


