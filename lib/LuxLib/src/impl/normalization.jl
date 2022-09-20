# Generic Normalization Implementation
function _update_normalization_statistics(x::AbstractArray{<:Real, N},
                                          running_mean::AbstractArray{<:Real, N},
                                          running_var::AbstractArray{<:Real, N},
                                          batchmean::AbstractArray{<:Real, N},
                                          batchvar::AbstractArray{<:Real, N},
                                          momentum::Real, reduce_dims) where {N}
    sx = size(x)
    m = (eltype(x))(prod(sx[reduce_dims]))
    if last(reduce_dims) != N
        batchmean = mean(batchmean; dims=N)
        batchvar = mean(batchvar; dims=N)
    end
    running_mean = @. (1 - momentum) * running_mean + momentum * batchmean
    running_var = @. (1 - momentum) * running_var + momentum * batchvar * (m / (m - one(m)))
    return (running_mean, running_var)
end

@generated function _get_batch_statistics(x::AbstractArray, running_mean::R, running_var::R,
                                          reduce_dims, ::Val{training}, momentum::Real,
                                          epsilon::Real) where {R, training}
    calls = []
    if !training
        if R == Nothing
            push!(calls, :(batchmean = mean(x; dims=reduce_dims)))
            push!(calls,
                  :(batchvar = var(x; mean=batchmean, dims=reduce_dims, corrected=false)))
        else
            push!(calls, :((batchmean, batchvar) = (running_mean, running_var)))
        end
    else
        push!(calls, :(batchmean = mean(x; dims=reduce_dims)))
        push!(calls,
              :(batchvar = var(x; mean=batchmean, dims=reduce_dims, corrected=false)))

        if R != Nothing
            push!(calls,
                  :(_stats = _update_normalization_statistics(x, running_mean, running_var,
                                                              batchmean, batchvar, momentum,
                                                              reduce_dims)))
            push!(calls, :((running_mean, running_var) = _stats))
        end
    end
    push!(calls, :(return ((batchmean, batchvar), (running_mean, running_var))))
    return Expr(:block, calls...)
end

@generated function _affine_normalize(x::AbstractArray, xmean::ST, xvar::ST, scale::A,
                                      bias::A, epsilon::Real) where {ST, A}
    if A != Nothing
        return :(return scale .* (x .- xmean) ./ sqrt.(xvar .+ epsilon) .+ bias)
    else
        return :(return (x .- xmean) ./ sqrt.(xvar .+ epsilon))
    end
end

function _normalization_impl(x::AbstractArray, running_mean::R, running_var::R, scale::A,
                             bias::A, reduce_dims, training::Val, momentum::Real,
                             epsilon::Real) where {R, A}
    _stats = _get_batch_statistics(x, running_mean, running_var, reduce_dims, training,
                                   momentum, epsilon)
    _m = mean(x; dims=reduce_dims)
    _v = var(x; dims=reduce_dims, corrected=false, mean=_m)
    (batchmean, batchvar), (running_mean, running_var) = _stats
    x_norm = _affine_normalize(x, batchmean, batchvar, scale, bias, epsilon)
    return (x_norm, running_mean, running_var)
end

function _normalization(x::AbstractArray, running_mean::Union{AbstractVector, Nothing},
                        running_var::Union{AbstractVector, Nothing},
                        scale::Union{AbstractVector, Nothing},
                        bias::Union{AbstractVector, Nothing}, reduce_dims, training::Val,
                        momentum::Real, epsilon::Real)
    rm_ = _reshape_into_proper_shape(running_mean, x)
    rv_ = _reshape_into_proper_shape(running_var, x)
    s_ = _reshape_into_proper_shape(scale, x)
    b_ = _reshape_into_proper_shape(bias, x)
    x_, rm, rv = _normalization_impl(x, rm_, rv_, s_, b_, reduce_dims, training, momentum,
                                     epsilon)
    return x_, _vec(rm), _vec(rv)
end