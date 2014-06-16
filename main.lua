require 'sys'
require 'xlua'
require 'torch'
require 'nn'

require 'Adagrad'
require 'KLDCriterion'

require 'LinearCR'
require 'Reparametrize'
require 'SpatialDeconvolution'
require 'SpatialZeroPaddingC'

require 'load'

dname,fname = sys.fpath()
cmd = torch.CmdLine()
cmd:text()
cmd:text('Deconvolutional network')
cmd:text()
cmd:text('Options:')
cmd:option('-save', fname:gsub('.lua',''), 'subdirectory to save/log experiments in')
-- cmd:option('-network', '', 'reload pretrained network')

cmd:option('-seed', true, 'fixed input seed for repeatable experiments')
cmd:option('-threads', 2, 'nb of threads to use')
cmd:text()
opt = cmd:parse(arg)

if opt.seed then
    torch.manualSeed(1)
end

require (opt.save .. '/config')

BCE = nn.BCECriterion()
BCE.sizeAverage = false
KLD = nn.KLDCriterion()

opfunc = function(batch) 
    model:zeroGradParameters()
    local f = model:forward(batch)
    -- local target = batch[{{},{},{3,34},{3,34}}]:reshape(100,total_output_size)
    local target = batch:double():reshape(100,total_output_size)
    local err = BCE:forward(f, target)
    local df_dw = BCE:backward(f, target)

    model:backward(batch,df_dw)

    local KLDerr = KLD:forward(model:get(1).output, target)
    local dKLD_dw = KLD:backward(model:get(1).output, target)

    encoderwithz:backward(batch,dKLD_dw)

    local lowerbound = err  + KLDerr
    local weights, grads = model:parameters()

    return weights, grads, lowerbound
end

function getLowerbound(data)
    local lowerbound = 0
     for i = 1, data:size(1), batchSize do
        local iend = math.min(data:size(1),i+batchSize-1)
        xlua.progress(iend, data:size(1))

        local batch = data[{{i,iend},{}}]
        local f = model:forward(batch)
        local target = batch:reshape(100,total_output_size)
        local err = BCE:forward(f, target)

        local KLDerr = KLD:forward(model:get(1).output, target)

        lowerbound = lowerbound + err + KLDerr
    end
    return lowerbound
end

epoch = 0

h = adaGradInit(trainData.data, opfunc, batchSize, initrounds)

lowerboundlist = {}
lowerbound_test_list = {}

while true do
    epoch = epoch + 1
    local lowerbound = 0
    local time = sys.clock()
    local shuffle = torch.randperm(trainData.data:size(1))
    local N = trainData.data:size(1)
    local N_test = testData.data:size(1)

    for i = 1, N, batchSize do
        local iend = math.min(N,i+batchSize-1)
        xlua.progress(iend, N)

        local batch = torch.CudaTensor(iend-i+1,trainData.data:size(2),input_size,input_size)

        local k = 1
        for j = i,iend do
            batch[k] = trainData.data[shuffle[j]]:clone() 
            k = k + 1
        end

        batchlowerbound = adaGradUpdate(batch,N, learningRate, opfunc, h)
        lowerbound = lowerbound + batchlowerbound
    end
    print("Epoch: " .. epoch .. " Lowerbound: " .. lowerbound/N .. " time: " .. sys.clock() - time)
    table.insert(lowerboundlist, lowerbound/N)

    if epoch % 5 == 0 then
        print('Calculating test lowerbound')
        lowerbound_test = getLowerbound(testData.data)
        table.insert(lowerbound_test_list, lowerbound_test)
        print('testlowerbound = ')
        print(lowerbound_test/N_test)
        print("Saving weights...")
        weights, gradients = model:getParameters()

        torch.save(opt.save .. '/model', model)
        torch.save(opt.save .. '/weights.t7', weights)
        torch.save(opt.save .. '/adagrad.t7', h)
        torch.save(opt.save .. '/lowerbound.t7', torch.Tensor(lowerboundlist))
        torch.save(opt.save .. '/lowerbound_test.t7', torch.Tensor(lowerbound_test_list))
    end
end
