batchSize = 100 -- size of mini-batches
learningRate = 0.02 -- Learning rate used in AdaGrad

initrounds = 15 -- Amount of intialization rounds in AdaGrad

trsize = 50000 -- Size of training set
tesize = 10000 -- Size of test set

-- Loading data
-- trainData is table with field 'data' which contains the data
trainData, testData = loadMnist(trsize,tesize)

-- Model Specific parameters
filter_size = 5
filter_size_2 = 5
stride = 4
dim_hidden = 25
input_size = 28 --NB this is done later (line 129)
pad1 = 1 --NB new size must be divisible with filtersize
pad2 = 0
pad_2 = (filter_size_2-1)/2
colorchannels = 1
total_output_size = colorchannels * input_size ^ 2
feature_maps = 32
feature_maps_2 = feature_maps*2

hidden_dec = 25

map_size = 7
map_size_2 = map_size
factor = input_size/map_size

--layer1
encoder = nn.Sequential()
encoder:add(nn.SpatialZeroPadding(pad1,pad2,pad1,pad2))
encoder:add(nn.SpatialConvolution(1,feature_maps,filter_size,filter_size,stride,stride))
encoder:add(nn.Threshold(0,1e-6))
--layer2
encoder:add(nn.SpatialZeroPadding(pad_2,pad_2,pad_2,pad_2))
encoder:add(nn.SpatialConvolution(feature_maps,feature_maps_2,filter_size_2,filter_size_2,1,1))
encoder:add(nn.Threshold(0,1e-6))
encoder:add(nn.Reshape(feature_maps_2 * map_size_2^2))

local z = nn.ConcatTable()
z:add(nn.LinearCR(feature_maps_2 * map_size_2^2, dim_hidden))
z:add(nn.LinearCR(feature_maps_2 * map_size_2^2, dim_hidden))

encoder:add(z)

local decoder = nn.Sequential()
decoder:add(nn.LinearCR(dim_hidden, feature_maps_2 * map_size_2^2))
decoder:add(nn.Threshold(0,1e-6))
--layer2
decoder:add(nn.Reshape(batchSize,feature_maps_2,map_size,map_size))
decoder:add(nn.SpatialZeroPadding(pad_2,pad_2,pad_2,pad_2))
decoder:add(nn.SpatialConvolution(feature_maps_2,feature_maps,filter_size_2,filter_size_2,1,1))
--layer1
decoder:add(nn.Reshape((map_size^2)*batchSize,feature_maps))
decoder:add(nn.LinearCR(feature_maps,hidden_dec))
decoder:add(nn.Threshold(0,1e-6))
decoder:add(nn.LinearCR(hidden_dec,colorchannels*factor*factor)) --hidden_dec should be in order of: featuremaps * filtersize^2 / (16+factor^2)
decoder:add(nn.Sigmoid())
decoder:add(nn.Reshape(batchSize,total_output_size))

model = nn.Sequential()
model:add(encoder)
model:add(nn.Reparametrize(dim_hidden))
model:add(decoder)