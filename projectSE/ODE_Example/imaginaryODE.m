function fv = imaginaryODE(t,yv)
  % Construct y from the real and imaginary components
  y = yv(1) + i*yv(2);            

  % Evaluate the function
  yp = complexf(t,y);             

  % Return real and imaginary in separate components
  fv = [real(yp); imag(yp)]; 
end    

function f = complexf(t,y)
  f = y.*t + 2*i;
end