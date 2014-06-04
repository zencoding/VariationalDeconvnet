require 'sys'
require 'torch'
require 'nn'

require 'linearCR'
require 'Reparametrize'
require 'Adagrad'
require 'SpatialDeconvolution'
require 'GaussianCriterion'
require 'KLDCriterion'

------------------------------------------------------------
-- convolutional network
------------------------------------------------------------
-- Grey Images
-- stage 1 : 3 input channels, 10 output, 5x5 filter, 2x2 stride
local filter_size = 4
local stride = 4
local dim_hidden = 100
local input_size = 32

-- NOT GENERIC 
local map_size = (input_size / stride) ^ 2
local feature_maps = 10

encoder = nn.Sequential()
encoder:add(nn.SpatialConvolution(3,feature_maps,filter_size,filter_size,stride,stride))
encoder:add(nn.SoftPlus())
encoder:add(nn.Reshape(feature_maps * map_size))

z = nn.ConcatTable()
z:add(nn.LinearCR(feature_maps * map_size, dim_hidden))
z:add(nn.LinearCR(feature_maps * map_size, dim_hidden))

encoder:add(z)

decoder = nn.Sequential()
decoder:add(nn.LinearCR(dim_hidden, feature_maps * map_size))
decoder:add(nn.Reshape(map_size,feature_maps))
decoder:add(nn.SpatialDeconvolution(feature_maps,3,stride))

model = nn.Sequential()
model:add(encoder)
model:add(nn.Reparametrize(dim_hidden))
model:add(decoder)

Gaussian = nn.GaussianCriterion()
KLD = nn.KLDCriterion()

opfunc = function(batch) 
    model:zeroGradParameters()

    f = model:forward(batch)
    err = Gaussian:forward(f, batch)
    df_dw = Gaussian:backward(f, batch)
    model:backward(batch,df_dw)

    KLDerr = KLD:forward(model:get(1).output, batch)
    dKLD_dw = KLD:backward(model:get(1).output, batch)
    encoder:backward(batch,dKLD_dw)

    lowerbound = err  + KLDerr
    weights, grads = model:parameters()


    return weights, grads, lowerbound
end

local trsize = 20000
local tesize = 10000


-- load dataset
trainData = {
   data = torch.Tensor(trsize, 3072),
   labels = torch.Tensor(trsize),
   size = function() return trsize end
}

for i = 0,1 do
  subset = torch.load('cifar-10-batches-t7/data_batch_' .. (i+1) .. '.t7', 'ascii')
  trainData.data[{ {i*10000+1, (i+1)*10000} }] = subset.data:t()
  trainData.labels[{ {i*10000+1, (i+1)*10000} }] = subset.labels
end

-- trainData.data = trainData.data:double()

trainData.labels = trainData.labels + 1

subset = torch.load('cifar-10-batches-t7/test_batch.t7', 'ascii')
testData = {
   data = subset.data:t():double(),
   labels = subset.labels[1]:double(),
   size = function() return tesize end
}
testData.labels = testData.labels + 1

-- reshape data
trainData.data = trainData.data:reshape(trsize,3,32,32)
testData.data = testData.data:reshape(tesize,3,32,32)

local epoch = 0
local batchSize = 100

while true do
    epoch = epoch + 1
    local lowerbound = 0
    local time = sys.clock()
    local shuffle = torch.randperm(trainData.data:size(1))
    local N = trainData.data:size(1)

    for i = 1, N, batchSize do
        local iend = math.min(N,i+batchSize-1)
        -- xlua.progress(iend, N)

        local batch = torch.Tensor(iend-i+1,trainData.data:size(2),32,32)

        local k = 1
        for j = i,iend do
            batch[k] = trainData.data[shuffle[j]]:clone() 
            k = k + 1
        end

        batchlowerbound = adaGradUpdate(batch, opfunc, h)
        lowerbound = lowerbound + batchlowerbound
    end
end